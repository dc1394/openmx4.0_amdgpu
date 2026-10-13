#!/usr/bin/env python3
"""Host-only tests for MAGMA provider selection; no ROCm or GPU required.

Use a recording compiler to test the real Makefile dependency graph, compile
the production MAGMA call adapter against stock 2.10.0 declarations extracted
from the bundled archive, and preprocess the full bridge with empty SDK
headers. These checks do not compile/link OpenMX with a real HIP SDK and do
not test numerical results.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

from run_gpu_eigen_dispatch import function


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{command!r}\n{result.stdout}\n{result.stderr}")
    return result


def make_checks(root, tmp):
    build = tmp / "build"
    build.mkdir()
    shutil.copy(root / "source/makefile", build / "makefile")
    for name in ("magma_openmx.cu", "openmx_common.h", "openmx_stdout_level.h", "openmx_gpu_arch_policy.h"):
        (build / name).touch()
    installed = tmp / "installed"
    (installed / "include").mkdir(parents=True)
    (installed / "lib").mkdir()
    library = installed / "lib/libmagma.so"
    library.touch()
    sentinel = installed / "do-not-delete"
    sentinel.write_text("installed library contents\n")
    bundled = build / "third_party/magma"
    (bundled / "lib").mkdir(parents=True)
    for name in ("third_party/magma/magma-2.10.0.tar.gz", "third_party/magma.openmx.make.inc",
                 "third_party/magma-ozaki2.patch", "third_party/magma/.openmx-magma-2.10.0.stamp",
                 "third_party/magma/lib/libmagma.a", "gemmul8.a"):
        (build / name).touch()
    recorder = tmp / "record.py"
    recorder.write_text('''import json, sys
from pathlib import Path
with Path("commands.jsonl").open("a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
Path(sys.argv[sys.argv.index("-o") + 1]).touch()
''')
    import sys
    base = ["make", "--no-print-directory", "-j2", "--old-file=gemmul8.a", "CLANG=true", "FLANG=true", "MPICC=true",
            "MPIF90=true", "ARCH=gfx942", f"HIPCC={sys.executable} {recorder}",
            f"CC={sys.executable} {recorder}", "OBJS=magma_openmx.o", "GEMMUL8_LIB=gemmul8.a", "LIB="]
    system = ["MAGMA_PROVIDER=system", f"MAGMA_INCLUDE_DIR={installed / 'include'}", f"MAGMA_LIB={library}"]
    def make(*args):
        return run(base + list(args), cwd=build)
    def count():
        return len((build / "commands.jsonl").read_text().splitlines())
    make("openmx", *system)
    assert count() == 2  # compile and link
    make("openmx", *system)
    assert count() == 2  # unchanged settings do not rebuild
    make("openmx")
    assert count() == 4  # default is bundled
    make("openmx", *system)
    assert count() == 6  # switching back must not reuse the bundled object
    make("openmx", *system, "MAGMA_LDFLAGS=-Wl,-rpath,/new-runtime-path")
    assert count() == 8
    make("openmx", *system, "MAGMA_LDFLAGS=-Wl,-rpath,/new-runtime-path")
    assert count() == 8
    other = installed / "other-headers"
    other.mkdir()
    make("openmx", *system, f"MAGMA_INCLUDE_DIR={other}")
    assert count() == 10
    otherlib = installed / "lib/libmagma.so.2"
    otherlib.touch()
    make("openmx", *system, f"MAGMA_LIB={otherlib}")
    assert count() == 12
    commands = (build / "commands.jsonl").read_text()
    assert "-DOPENMX_MAGMA_HAS_OZAKI2=0" in commands
    assert "-DOPENMX_MAGMA_HAS_OZAKI2=1" in commands
    assert f"-I{installed / 'include'}" in commands
    assert str(library) in commands and f"-Wl,-rpath,{installed / 'lib'}/" in commands
    dry = make("-n", "clean", *system, f"MAGMA_DIR={installed}").stdout
    assert "find " not in dry and str(installed) not in dry
    # Deliberately set MAGMA_DIR to the installation to prove system mode never
    # executes bundled cleanup, even with this otherwise discouraged setting.
    make("magma-clean", *system, f"MAGMA_DIR={installed}")
    assert library.exists() and sentinel.read_text() == "installed library contents\n"
    missing = subprocess.run(base + ["magma_openmx.o", *system, "MAGMA_LIB=/missing/libmagma.so"],
                             cwd=build, text=True, capture_output=True)
    assert missing.returncode != 0 and "No rule to make target" in missing.stderr
    invalid = subprocess.run(base + ["-n", "MAGMA_PROVIDER=typo"], cwd=build, text=True, capture_output=True)
    assert invalid.returncode != 0 and "MAGMA_PROVIDER must be bundled or system" in invalid.stderr
    print("PASS Makefile: default/system, compile/link paths, incremental switches, missing library, safe clean")


ADAPTER_TYPES = r'''
#include <cstddef>
using magma_int_t = int;
enum magma_vec_t { MagmaVec };
enum magma_uplo_t { MagmaLower };
enum magma_range_t { MagmaRangeAll, MagmaRangeI };
constexpr int MAGMA_SUCCESS = 0;
struct magmaDoubleComplex { double x, y; };
using magmaDouble_ptr = double *;
using magmaDoubleComplex_ptr = magmaDoubleComplex *;
#define MAGMA_Z_ZERO magmaDoubleComplex{0, 0}
#define MAGMA_Z_REAL(z) ((z).x)
double *g_host_matrix, *g_work, *g_z_rwork;
magmaDoubleComplex *g_z_host_matrix, *g_z_work;
magma_int_t *g_iwork, *g_z_iwork;
int ensure_magma_initialized();
int ensure_host_matrix(size_t);
int ensure_z_host_matrix(size_t);
int ensure_work(int, int);
int ensure_z_work(int, int, int);
int hipDeviceSynchronize();
'''


def adapter_checks(root, tmp, cxx):
    source = (root / "source/magma_openmx.cu").read_text()
    declarations = []
    with tarfile.open(root / "source/third_party/magma/magma-2.10.0.tar.gz") as archive:
        for precision, name in (("d", "magma_dsyevdx_gpu"), ("z", "magma_zheevdx_gpu")):
            header = archive.extractfile(f"magma-2.10.0/include/magma_{precision}.h").read().decode()
            declaration = re.search(r"magma_int_t\s+" + name + r"\([\s\S]*?\);", header).group()
            directive = "#define MAGMA_COMPLEX\n" if precision == "z" else "#undef MAGMA_COMPLEX\n"
            declarations.append(directive + 'extern "C" ' + declaration)
    stock = "\n".join(declarations)
    patched = stock.replace("magma_dsyevdx_gpu", "magma_dsyevdx_ozaki2_gpu").replace(
        "magma_zheevdx_gpu", "magma_zheevdx_ozaki2_gpu")
    for mode in (0, 1):
        program = ADAPTER_TYPES + stock
        if mode:
            program += "\n" + patched + '\nextern "C" void magma_ozaki2_release_workspaces();\n'
        program += "\n" + function(source, "magma_evdx_locked")
        program += "\n" + function(source, "openmx_magma_ozaki2_release")
        cpp, obj = tmp / f"adapter{mode}.cpp", tmp / f"adapter{mode}.o"
        cpp.write_text(program)
        run([cxx, "-std=c++20", "-Wall", "-Wextra", "-Werror", f"-DOPENMX_MAGMA_HAS_OZAKI2={mode}",
             "-c", str(cpp), "-o", str(obj)])
        symbols = run(["nm", "-u", str(obj)]).stdout
        for name in ("magma_dsyevdx_ozaki2_gpu", "magma_zheevdx_ozaki2_gpu", "magma_ozaki2_release_workspaces"):
            assert (name in symbols) == bool(mode), (mode, name)
        assert "magma_dsyevdx_gpu" in symbols and "magma_zheevdx_gpu" in symbols
    # Check all branches in the full TU, including ordinary workspace release.
    headers = tmp / "headers"
    (headers / "hip").mkdir(parents=True)
    (headers / "hipsolver").mkdir()
    (headers / "magma_config.h").write_text("#define MAGMA_HAVE_HIP\n")
    for name in ("magma_v2.h", "hip/hip_runtime.h", "hipsolver/hipsolver.h"):
        (headers / name).touch()
    preprocessed = run([cxx, "-E", "-P", "-x", "c++", "-DOPENMX_MAGMA_HAS_OZAKI2=0",
                        "-I" + str(headers), str(root / "source/magma_openmx.cu")]).stdout
    assert not re.search(r"\bmagma_\w*ozaki2\w*\s*\(", preprocessed)
    dc = (root / "source/Divide_Conquer_LNO.c").read_text()
    assert "magma_ozaki2_release_workspaces" not in dc
    print("PASS adapter: stock 2.10.0 declarations, no private symbols in system object/full preprocessor output")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cxx", default="g++")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    # Avoid unrelated make overrides from the caller affecting these fixtures.
    for key in ("MAKEFLAGS", "MFLAGS", "MAKEOVERRIDES"):
        os.environ.pop(key, None)
    with tempfile.TemporaryDirectory(prefix="openmx-system-magma-") as directory:
        tmp = Path(directory)
        make_checks(root, tmp)
        adapter_checks(root, tmp, args.cxx)
    print("system_magma_build: host-only checks passed; real HIP build and GPU numerics NOT tested")


if __name__ == "__main__":
    main()
