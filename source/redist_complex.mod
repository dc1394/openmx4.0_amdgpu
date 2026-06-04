!mod$ v1 sum:9561645dddf285b9
module redist_complex
contains
subroutine redist_band_complex_double(obj,a_mat,a_dev,lda,na,nblk,nbw,matrixcols,mpi_comm_rows,mpi_comm_cols,communicator,ab,usegpu)
integer(4),intent(in)::obj
integer(4),intent(in)::lda
integer(4),intent(in)::matrixcols
complex(8),intent(in)::a_mat(1_8:int(lda,kind=8),1_8:int(matrixcols,kind=8))
integer(8)::a_dev
integer(4),intent(in)::na
integer(4),intent(in)::nblk
integer(4),intent(in)::nbw
integer(4),intent(in)::mpi_comm_rows
integer(4),intent(in)::mpi_comm_cols
integer(4),intent(in)::communicator
complex(8),intent(out)::ab(:,:)
logical(4),intent(in)::usegpu
end
end
