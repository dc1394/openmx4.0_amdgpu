!mod$ v1 sum:25e1b915048d9ac7
!need$ 0bde2ac47243ead2 i iso_c_binding
module precision
use,intrinsic::iso_c_binding,only:c_float
use,intrinsic::iso_c_binding,only:c_double
use,intrinsic::iso_c_binding,only:c_float_complex
use,intrinsic::iso_c_binding,only:c_double_complex
use,intrinsic::iso_c_binding,only:c_int32_t
use,intrinsic::iso_c_binding,only:c_int64_t
use,intrinsic::iso_c_binding,only:c_int
integer(4),parameter::rk8=8_4
integer(4),parameter::rk4=4_4
integer(4),parameter::ck8=8_4
integer(4),parameter::ck4=4_4
integer(4),parameter::ik=4_4
integer(4),parameter::lik=8_4
end
