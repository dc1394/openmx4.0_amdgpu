!mod$ v1 sum:3905340c3745e96a
module pack_unpack_cpu_real
contains
subroutine pack_row_real_cpu_openmp_double(obj,a,row,n,stripe_width,stripe_count,max_threads,thread_width,l_nev)
integer(4),intent(in)::obj
real(8),intent(in)::a(:,:,:,:)
real(8)::row(:)
integer(4),intent(in)::n
integer(4),intent(in)::stripe_width
integer(4),intent(in)::stripe_count
integer(4),intent(in)::max_threads
integer(4),intent(in)::thread_width
integer(4),intent(in)::l_nev
end
subroutine unpack_row_real_cpu_openmp_double(obj,a,row,n,my_thread,stripe_count,thread_width,stripe_width,l_nev)
integer(4),intent(in)::obj
real(8)::a(:,:,:,:)
real(8),intent(in)::row(:)
integer(4),intent(in)::n
integer(4),intent(in)::my_thread
integer(4),intent(in)::stripe_count
integer(4),intent(in)::thread_width
integer(4),intent(in)::stripe_width
integer(4),intent(in)::l_nev
end
end
