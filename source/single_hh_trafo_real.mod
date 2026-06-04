!mod$ v1 sum:de43beb8d6fea60f
module single_hh_trafo_real
contains
subroutine single_hh_trafo_real_cpu_openmp_double(q,hh,nb,nq,ldq)
integer(4),intent(in)::ldq
integer(4),intent(in)::nb
real(8),intent(inout)::q(1_8:int(ldq,kind=8),1_8:int(nb,kind=8))
real(8),intent(in)::hh(1_8:int(nb,kind=8))
integer(4),intent(in)::nq
end
end
