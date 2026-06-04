!mod$ v1 sum:8bd8df79e332ed9e
module elpa2_workload
contains
subroutine determine_workload(obj,na,nb,nprocs,limits)
integer(4),intent(in)::obj
integer(4),intent(in)::na
integer(4),intent(in)::nb
integer(4),intent(in)::nprocs
integer(4),intent(out)::limits(0_8:int(nprocs,kind=8))
end
subroutine divide_band(obj,nblocks_total,n_pes,block_limits)
integer(4),intent(in)::obj
integer(4),intent(in)::nblocks_total
integer(4),intent(in)::n_pes
integer(4),intent(out)::block_limits(0_8:int(n_pes,kind=8))
end
end
