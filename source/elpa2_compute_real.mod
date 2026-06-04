!mod$ v1 sum:442803f6b4d9d1a9
!need$ efb71c1bce5c1393 n aligned_mem
!need$ 16f70eab2d389133 n elpa1_compute_real
!need$ 25e1b915048d9ac7 n precision
!need$ bb381bf46e508468 i __fortran_builtins
!need$ 2e41453616bc8953 n elpa_utilities
!need$ f9cce8e6d74b58c7 n mpi
module elpa2_compute_real
use elpa_utilities,only:output_unit
use elpa_utilities,only:error_unit
use elpa_utilities,only:pcol
use elpa_utilities,only:prow
use elpa_utilities,only:map_global_array_index_to_local_index
use elpa_utilities,only:local_index
use elpa_utilities,only:least_common_multiple
use elpa_utilities,only:check_alloc
use elpa_utilities,only:check_alloc_cuda_f
use elpa_utilities,only:check_dealloc_cuda_f
use elpa_utilities,only:check_memcpy_cuda_f
use elpa1_compute_real,only:hh_transform_real
use elpa1_compute_real,only:elpa_reduce_add_vectors_real
use elpa1_compute_real,only:elpa_transpose_vectors_real
use elpa1_compute_real,only:elpa_transpose_vectors_real_double
use elpa1_compute_real,only:elpa_reduce_add_vectors_real_double
use elpa1_compute_real,only:solve_tridi_double
use elpa1_compute_real,only:solve_tridi_double_impl
use elpa1_compute_real,only:hh_transform_real_double
use mpi,only:mpi_status
use mpi,only:mpi_comm
use mpi,only:mpi_datatype
use mpi,only:mpi_errhandler
use mpi,only:mpi_file
use mpi,only:mpi_group
use mpi,only:mpi_info
use mpi,only:mpi_message
use mpi,only:mpi_op
use mpi,only:mpi_request
use mpi,only:mpi_session
use mpi,only:mpi_win
use mpi,only:ompi_comm_op_eq
use mpi,only:ompi_datatype_op_eq
use mpi,only:ompi_errhandler_op_eq
use mpi,only:ompi_file_op_eq
use mpi,only:ompi_group_op_eq
use mpi,only:ompi_info_op_eq
use mpi,only:ompi_message_op_eq
use mpi,only:ompi_op_op_eq
use mpi,only:ompi_request_op_eq
use mpi,only:ompi_win_op_eq
use mpi,only:ompi_comm_op_ne
use mpi,only:ompi_datatype_op_ne
use mpi,only:ompi_errhandler_op_ne
use mpi,only:ompi_file_op_ne
use mpi,only:ompi_group_op_ne
use mpi,only:ompi_info_op_ne
use mpi,only:ompi_message_op_ne
use mpi,only:ompi_op_op_ne
use mpi,only:ompi_request_op_ne
use mpi,only:ompi_win_op_ne
use mpi,only:ompi_major_version
use mpi,only:ompi_minor_version
use mpi,only:ompi_release_version
use mpi,only:mpi_offset_kind
use mpi,only:mpi_address_kind
use mpi,only:mpi_integer_kind
use mpi,only:mpi_count_kind
use mpi,only:mpi_status_size
use mpi,only:mpi_max_processor_name
use mpi,only:mpi_max_error_string
use mpi,only:mpi_max_object_name
use mpi,only:mpi_max_library_version_string
use mpi,only:mpi_max_info_key
use mpi,only:mpi_max_info_val
use mpi,only:mpi_max_port_name
use mpi,only:mpi_max_datarep_string
use mpi,only:mpi_max_pset_name_len
use mpi,only:mpi_max_stringtag_len
use mpi,only:mpi_subarrays_supported
use mpi,only:mpi_async_protects_nonblocking
use mpi,only:mpi_any_source
use mpi,only:mpi_any_tag
use mpi,only:mpi_appnum
use mpi,only:mpi_bsend_overhead
use mpi,only:mpi_cart
use mpi,only:mpi_combiner_contiguous
use mpi,only:mpi_combiner_darray
use mpi,only:mpi_combiner_dup
use mpi,only:mpi_combiner_f90_complex
use mpi,only:mpi_combiner_f90_integer
use mpi,only:mpi_combiner_f90_real
use mpi,only:mpi_combiner_hindexed
use mpi,only:mpi_combiner_hindexed_block
use mpi,only:mpi_combiner_hindexed_integer
use mpi,only:mpi_combiner_hvector
use mpi,only:mpi_combiner_hvector_integer
use mpi,only:mpi_combiner_indexed
use mpi,only:mpi_combiner_indexed_block
use mpi,only:mpi_combiner_named
use mpi,only:mpi_combiner_resized
use mpi,only:mpi_combiner_struct
use mpi,only:mpi_combiner_struct_integer
use mpi,only:mpi_combiner_subarray
use mpi,only:mpi_combiner_vector
use mpi,only:mpi_comm_type_hw_guided
use mpi,only:mpi_comm_type_hw_unguided
use mpi,only:mpi_comm_type_shared
use mpi,only:mpi_congruent
use mpi,only:mpi_distribute_block
use mpi,only:mpi_distribute_cyclic
use mpi,only:mpi_distribute_dflt_darg
use mpi,only:mpi_distribute_none
use mpi,only:mpi_dist_graph
use mpi,only:mpi_error
use mpi,only:mpi_err_access
use mpi,only:mpi_err_amode
use mpi,only:mpi_err_arg
use mpi,only:mpi_err_assert
use mpi,only:mpi_err_bad_file
use mpi,only:mpi_err_base
use mpi,only:mpi_err_buffer
use mpi,only:mpi_err_comm
use mpi,only:mpi_err_conversion
use mpi,only:mpi_err_count
use mpi,only:mpi_err_dims
use mpi,only:mpi_err_disp
use mpi,only:mpi_err_dup_datarep
use mpi,only:mpi_err_file
use mpi,only:mpi_err_file_exists
use mpi,only:mpi_err_file_in_use
use mpi,only:mpi_err_group
use mpi,only:mpi_err_info
use mpi,only:mpi_err_info_key
use mpi,only:mpi_err_info_nokey
use mpi,only:mpi_err_info_value
use mpi,only:mpi_err_intern
use mpi,only:mpi_err_in_status
use mpi,only:mpi_err_io
use mpi,only:mpi_err_keyval
use mpi,only:mpi_err_lastcode
use mpi,only:mpi_err_locktype
use mpi,only:mpi_err_name
use mpi,only:mpi_err_not_same
use mpi,only:mpi_err_no_mem
use mpi,only:mpi_err_no_space
use mpi,only:mpi_err_no_such_file
use mpi,only:mpi_err_op
use mpi,only:mpi_err_other
use mpi,only:mpi_err_pending
use mpi,only:mpi_err_port
use mpi,only:mpi_err_proc_aborted
use mpi,only:mpi_err_proc_failed
use mpi,only:mpi_err_proc_failed_pending
use mpi,only:mpi_err_quota
use mpi,only:mpi_err_rank
use mpi,only:mpi_err_read_only
use mpi,only:mpi_err_request
use mpi,only:mpi_err_revoked
use mpi,only:mpi_err_rma_attach
use mpi,only:mpi_err_rma_conflict
use mpi,only:mpi_err_rma_flavor
use mpi,only:mpi_err_rma_range
use mpi,only:mpi_err_rma_shared
use mpi,only:mpi_err_rma_sync
use mpi,only:mpi_err_root
use mpi,only:mpi_err_service
use mpi,only:mpi_err_session
use mpi,only:mpi_err_size
use mpi,only:mpi_err_spawn
use mpi,only:mpi_err_tag
use mpi,only:mpi_err_topology
use mpi,only:mpi_err_truncate
use mpi,only:mpi_err_type
use mpi,only:mpi_err_unknown
use mpi,only:mpi_err_unsupported_datarep
use mpi,only:mpi_err_unsupported_operation
use mpi,only:mpi_err_value_too_large
use mpi,only:mpi_err_win
use mpi,only:mpi_ft
use mpi,only:mpi_graph
use mpi,only:mpi_host
use mpi,only:mpi_ident
use mpi,only:mpi_io
use mpi,only:mpi_keyval_invalid
use mpi,only:mpi_lastusedcode
use mpi,only:mpi_lock_exclusive
use mpi,only:mpi_lock_shared
use mpi,only:mpi_mode_nocheck
use mpi,only:mpi_mode_noprecede
use mpi,only:mpi_mode_noput
use mpi,only:mpi_mode_nostore
use mpi,only:mpi_mode_nosucceed
use mpi,only:mpi_order_c
use mpi,only:mpi_order_fortran
use mpi,only:mpi_proc_null
use mpi,only:mpi_root
use mpi,only:mpi_similar
use mpi,only:mpi_source
use mpi,only:mpi_subversion
use mpi,only:mpi_success
use mpi,only:mpi_tag
use mpi,only:mpi_tag_ub
use mpi,only:mpi_thread_funneled
use mpi,only:mpi_thread_multiple
use mpi,only:mpi_thread_serialized
use mpi,only:mpi_thread_single
use mpi,only:mpi_typeclass_complex
use mpi,only:mpi_typeclass_integer
use mpi,only:mpi_typeclass_real
use mpi,only:mpi_t_err_cannot_init
use mpi,only:mpi_t_err_cvar_set_never
use mpi,only:mpi_t_err_cvar_set_not_now
use mpi,only:mpi_t_err_invalid
use mpi,only:mpi_t_err_invalid_handle
use mpi,only:mpi_t_err_invalid_index
use mpi,only:mpi_t_err_invalid_item
use mpi,only:mpi_t_err_invalid_session
use mpi,only:mpi_t_err_memory
use mpi,only:mpi_t_err_not_initialized
use mpi,only:mpi_t_err_out_of_handles
use mpi,only:mpi_t_err_out_of_sessions
use mpi,only:mpi_t_err_pvar_no_atomic
use mpi,only:mpi_t_err_pvar_no_startstop
use mpi,only:mpi_t_err_pvar_no_write
use mpi,only:mpi_undefined
use mpi,only:mpi_unequal
use mpi,only:mpi_universe_size
use mpi,only:mpi_version
use mpi,only:mpi_win_base
use mpi,only:mpi_win_create_flavor
use mpi,only:mpi_win_disp_unit
use mpi,only:mpi_win_flavor_allocate
use mpi,only:mpi_win_flavor_create
use mpi,only:mpi_win_flavor_dynamic
use mpi,only:mpi_win_flavor_shared
use mpi,only:mpi_win_model
use mpi,only:mpi_win_separate
use mpi,only:mpi_win_size
use mpi,only:mpi_win_unified
use mpi,only:mpi_wtime_is_global
use mpi,only:ompi_comm_type_board
use mpi,only:ompi_comm_type_cluster
use mpi,only:ompi_comm_type_core
use mpi,only:ompi_comm_type_cu
use mpi,only:ompi_comm_type_host
use mpi,only:ompi_comm_type_hwthread
use mpi,only:ompi_comm_type_l1cache
use mpi,only:ompi_comm_type_l2cache
use mpi,only:ompi_comm_type_l3cache
use mpi,only:ompi_comm_type_node
use mpi,only:ompi_comm_type_numa
use mpi,only:ompi_comm_type_socket
use mpi,only:mpi_2complex
use mpi,only:mpi_2double_complex
use mpi,only:mpi_2double_precision
use mpi,only:mpi_2int
use mpi,only:mpi_2integer
use mpi,only:mpi_2real
use mpi,only:mpi_aint
use mpi,only:mpi_band
use mpi,only:mpi_bor
use mpi,only:mpi_bxor
use mpi,only:mpi_byte
use mpi,only:mpi_char
use mpi,only:mpi_character
use mpi,only:mpi_comm_null
use mpi,only:mpi_comm_self
use mpi,only:mpi_comm_world
use mpi,only:mpi_complex
use mpi,only:mpi_complex16
use mpi,only:mpi_complex32
use mpi,only:mpi_complex4
use mpi,only:mpi_complex8
use mpi,only:mpi_count
use mpi,only:mpi_cxx_bool
use mpi,only:mpi_cxx_complex
use mpi,only:mpi_cxx_double_complex
use mpi,only:mpi_cxx_float_complex
use mpi,only:mpi_cxx_long_double_complex
use mpi,only:mpi_c_bool
use mpi,only:mpi_c_complex
use mpi,only:mpi_c_double_complex
use mpi,only:mpi_c_float_complex
use mpi,only:mpi_c_long_double_complex
use mpi,only:mpi_datatype_null
use mpi,only:mpi_double
use mpi,only:mpi_double_complex
use mpi,only:mpi_double_int
use mpi,only:mpi_double_precision
use mpi,only:mpi_errhandler_null
use mpi,only:mpi_errors_abort
use mpi,only:mpi_errors_are_fatal
use mpi,only:mpi_errors_return
use mpi,only:mpi_float
use mpi,only:mpi_float_int
use mpi,only:mpi_group_empty
use mpi,only:mpi_group_null
use mpi,only:mpi_info_env
use mpi,only:mpi_info_null
use mpi,only:mpi_int
use mpi,only:mpi_int16_t
use mpi,only:mpi_int32_t
use mpi,only:mpi_int64_t
use mpi,only:mpi_int8_t
use mpi,only:mpi_integer
use mpi,only:mpi_integer1
use mpi,only:mpi_integer16
use mpi,only:mpi_integer2
use mpi,only:mpi_integer4
use mpi,only:mpi_integer8
use mpi,only:mpi_land
use mpi,only:mpi_lb
use mpi,only:mpi_logical
use mpi,only:mpi_logical1
use mpi,only:mpi_logical2
use mpi,only:mpi_logical4
use mpi,only:mpi_logical8
use mpi,only:mpi_long
use mpi,only:mpi_long_double
use mpi,only:mpi_long_double_int
use mpi,only:mpi_long_int
use mpi,only:mpi_long_long
use mpi,only:mpi_long_long_int
use mpi,only:mpi_lor
use mpi,only:mpi_lxor
use mpi,only:mpi_max
use mpi,only:mpi_maxloc
use mpi,only:mpi_message_no_proc
use mpi,only:mpi_message_null
use mpi,only:mpi_min
use mpi,only:mpi_minloc
use mpi,only:mpi_no_op
use mpi,only:mpi_offset
use mpi,only:mpi_op_null
use mpi,only:mpi_packed
use mpi,only:mpi_prod
use mpi,only:mpi_real
use mpi,only:mpi_real16
use mpi,only:mpi_real2
use mpi,only:mpi_real4
use mpi,only:mpi_real8
use mpi,only:mpi_replace
use mpi,only:mpi_request_null
use mpi,only:mpi_session_null
use mpi,only:mpi_short
use mpi,only:mpi_short_int
use mpi,only:mpi_signed_char
use mpi,only:mpi_sum
use mpi,only:mpi_ub
use mpi,only:mpi_uint16_t
use mpi,only:mpi_uint32_t
use mpi,only:mpi_uint64_t
use mpi,only:mpi_uint8_t
use mpi,only:mpi_unsigned
use mpi,only:mpi_unsigned_char
use mpi,only:mpi_unsigned_long
use mpi,only:mpi_unsigned_long_long
use mpi,only:mpi_unsigned_short
use mpi,only:mpi_wchar
use mpi,only:mpi_win_null
use mpi,only:mpi_mode_append
use mpi,only:mpi_mode_create
use mpi,only:mpi_mode_delete_on_close
use mpi,only:mpi_mode_excl
use mpi,only:mpi_mode_rdonly
use mpi,only:mpi_mode_rdwr
use mpi,only:mpi_mode_sequential
use mpi,only:mpi_mode_unique_open
use mpi,only:mpi_mode_wronly
use mpi,only:mpi_seek_cur
use mpi,only:mpi_seek_end
use mpi,only:mpi_seek_set
use mpi,only:mpi_displacement_current
use mpi,only:mpi_file_null
use mpi,only:mpi_dup_fn
use mpi,only:mpi_null_copy_fn
use mpi,only:mpi_null_delete_fn
use mpi,only:mpi_comm_dup_fn
use mpi,only:mpi_comm_null_copy_fn
use mpi,only:mpi_comm_null_delete_fn
use mpi,only:mpi_type_dup_fn
use mpi,only:mpi_type_null_copy_fn
use mpi,only:mpi_type_null_delete_fn
use mpi,only:mpi_win_dup_fn
use mpi,only:mpi_win_null_copy_fn
use mpi,only:mpi_win_null_delete_fn
use mpi,only:mpi_conversion_fn_null
use mpi,only:mpi_abort
use mpi,only:mpi_accumulate
use mpi,only:mpi_add_error_class
use mpi,only:mpi_add_error_code
use mpi,only:mpi_add_error_string
use mpi,only:mpi_aint_add
use mpi,only:mpi_aint_diff
use mpi,only:mpi_allgather
use mpi,only:mpi_allgather_init
use mpi,only:mpi_allgatherv
use mpi,only:mpi_allgatherv_init
use mpi,only:mpi_alloc_mem_cptr
use mpi,only:mpi_allreduce
use mpi,only:mpi_allreduce_init
use mpi,only:mpi_alltoall
use mpi,only:mpi_alltoall_init
use mpi,only:mpi_alltoallv
use mpi,only:mpi_alltoallv_init
use mpi,only:mpi_alltoallw
use mpi,only:mpi_alltoallw_init
use mpi,only:mpi_barrier
use mpi,only:mpi_barrier_init
use mpi,only:mpi_bcast
use mpi,only:mpi_bcast_init
use mpi,only:mpi_bsend
use mpi,only:mpi_bsend_init
use mpi,only:mpi_buffer_attach
use mpi,only:mpi_buffer_detach
use mpi,only:mpi_cancel
use mpi,only:mpi_cart_coords
use mpi,only:mpi_cart_create
use mpi,only:mpi_cart_get
use mpi,only:mpi_cart_map
use mpi,only:mpi_cart_rank
use mpi,only:mpi_cart_shift
use mpi,only:mpi_cart_sub
use mpi,only:mpi_cartdim_get
use mpi,only:mpi_close_port
use mpi,only:mpi_comm_accept
use mpi,only:mpi_comm_call_errhandler
use mpi,only:mpi_comm_compare
use mpi,only:mpi_comm_connect
use mpi,only:mpi_comm_create
use mpi,only:mpi_comm_create_errhandler
use mpi,only:mpi_comm_create_group
use mpi,only:mpi_comm_create_keyval
use mpi,only:mpi_comm_delete_attr
use mpi,only:mpi_comm_disconnect
use mpi,only:mpi_comm_dup
use mpi,only:mpi_comm_dup_with_info
use mpi,only:mpi_comm_free
use mpi,only:mpi_comm_free_keyval
use mpi,only:mpi_comm_get_attr
use mpi,only:mpi_comm_get_errhandler
use mpi,only:mpi_comm_get_info
use mpi,only:mpi_comm_get_name
use mpi,only:mpi_comm_get_parent
use mpi,only:mpi_comm_group
use mpi,only:mpi_comm_idup
use mpi,only:mpi_comm_idup_with_info
use mpi,only:mpi_comm_join
use mpi,only:mpi_comm_rank
use mpi,only:mpi_comm_remote_group
use mpi,only:mpi_comm_remote_size
use mpi,only:mpi_comm_set_attr
use mpi,only:mpi_comm_set_errhandler
use mpi,only:mpi_comm_set_info
use mpi,only:mpi_comm_set_name
use mpi,only:mpi_comm_size
use mpi,only:mpi_comm_spawn
use mpi,only:mpi_comm_spawn_multiple
use mpi,only:mpi_comm_split
use mpi,only:mpi_comm_split_type
use mpi,only:mpi_comm_test_inter
use mpi,only:mpi_compare_and_swap
use mpi,only:mpi_dims_create
use mpi,only:mpi_dist_graph_create
use mpi,only:mpi_dist_graph_create_adjacent
use mpi,only:mpi_dist_graph_neighbors
use mpi,only:mpi_dist_graph_neighbors_count
use mpi,only:mpi_errhandler_free
use mpi,only:mpi_error_class
use mpi,only:mpi_error_string
use mpi,only:mpi_exscan
use mpi,only:mpi_exscan_init
use mpi,only:mpi_f_sync_reg
use mpi,only:mpi_fetch_and_op
use mpi,only:mpi_finalize
use mpi,only:mpi_finalized
use mpi,only:mpi_free_mem
use mpi,only:mpi_gather
use mpi,only:mpi_gather_init
use mpi,only:mpi_gatherv
use mpi,only:mpi_gatherv_init
use mpi,only:mpi_get
use mpi,only:mpi_get_accumulate
use mpi,only:mpi_get_address
use mpi,only:mpi_get_count
use mpi,only:mpi_get_elements
use mpi,only:mpi_get_elements_x
use mpi,only:mpi_get_library_version
use mpi,only:mpi_get_processor_name
use mpi,only:mpi_get_version
use mpi,only:mpi_graph_create
use mpi,only:mpi_graph_get
use mpi,only:mpi_graph_map
use mpi,only:mpi_graph_neighbors
use mpi,only:mpi_graph_neighbors_count
use mpi,only:mpi_graphdims_get
use mpi,only:mpi_grequest_complete
use mpi,only:mpi_grequest_start
use mpi,only:mpi_group_compare
use mpi,only:mpi_group_difference
use mpi,only:mpi_group_excl
use mpi,only:mpi_group_free
use mpi,only:mpi_group_incl
use mpi,only:mpi_group_intersection
use mpi,only:mpi_group_range_excl
use mpi,only:mpi_group_range_incl
use mpi,only:mpi_group_rank
use mpi,only:mpi_group_size
use mpi,only:mpi_group_translate_ranks
use mpi,only:mpi_group_union
use mpi,only:mpi_iallgather
use mpi,only:mpi_iallgatherv
use mpi,only:mpi_iallreduce
use mpi,only:mpi_ialltoall
use mpi,only:mpi_ialltoallv
use mpi,only:mpi_ialltoallw
use mpi,only:mpi_ibarrier
use mpi,only:mpi_ibcast
use mpi,only:mpi_ibsend
use mpi,only:mpi_iexscan
use mpi,only:mpi_igather
use mpi,only:mpi_igatherv
use mpi,only:mpi_improbe
use mpi,only:mpi_imrecv
use mpi,only:mpi_ineighbor_allgather
use mpi,only:mpi_ineighbor_allgatherv
use mpi,only:mpi_ineighbor_alltoall
use mpi,only:mpi_ineighbor_alltoallv
use mpi,only:mpi_ineighbor_alltoallw
use mpi,only:mpi_info_create
use mpi,only:mpi_info_create_env
use mpi,only:mpi_info_delete
use mpi,only:mpi_info_dup
use mpi,only:mpi_info_free
use mpi,only:mpi_info_get
use mpi,only:mpi_info_get_nkeys
use mpi,only:mpi_info_get_nthkey
use mpi,only:mpi_info_get_string
use mpi,only:mpi_info_get_valuelen
use mpi,only:mpi_info_set
use mpi,only:mpi_init
use mpi,only:mpi_init_thread
use mpi,only:mpi_initialized
use mpi,only:mpi_intercomm_create
use mpi,only:mpi_intercomm_merge
use mpi,only:mpi_iprobe
use mpi,only:mpi_irecv
use mpi,only:mpi_ireduce
use mpi,only:mpi_ireduce_scatter
use mpi,only:mpi_ireduce_scatter_block
use mpi,only:mpi_irsend
use mpi,only:mpi_is_thread_main
use mpi,only:mpi_iscan
use mpi,only:mpi_iscatter
use mpi,only:mpi_iscatterv
use mpi,only:mpi_isend
use mpi,only:mpi_isendrecv
use mpi,only:mpi_isendrecv_replace
use mpi,only:mpi_issend
use mpi,only:mpi_psend_init
use mpi,only:mpi_precv_init
use mpi,only:mpi_pready
use mpi,only:mpi_pready_list
use mpi,only:mpi_pready_range
use mpi,only:mpi_parrived
use mpi,only:mpi_lookup_name
use mpi,only:mpi_mprobe
use mpi,only:mpi_mrecv
use mpi,only:mpi_neighbor_allgather
use mpi,only:mpi_neighbor_allgather_init
use mpi,only:mpi_neighbor_allgatherv
use mpi,only:mpi_neighbor_allgatherv_init
use mpi,only:mpi_neighbor_alltoall
use mpi,only:mpi_neighbor_alltoall_init
use mpi,only:mpi_neighbor_alltoallv
use mpi,only:mpi_neighbor_alltoallv_init
use mpi,only:mpi_neighbor_alltoallw
use mpi,only:mpi_neighbor_alltoallw_init
use mpi,only:mpi_op_commutative
use mpi,only:mpi_op_create
use mpi,only:mpi_op_free
use mpi,only:mpi_open_port
use mpi,only:mpi_pack
use mpi,only:mpi_pack_external
use mpi,only:mpi_pack_external_size
use mpi,only:mpi_pack_size
use mpi,only:mpi_pcontrol
use mpi,only:mpi_probe
use mpi,only:mpi_publish_name
use mpi,only:mpi_put
use mpi,only:mpi_query_thread
use mpi,only:mpi_raccumulate
use mpi,only:mpi_recv
use mpi,only:mpi_recv_init
use mpi,only:mpi_reduce
use mpi,only:mpi_reduce_init
use mpi,only:mpi_reduce_local
use mpi,only:mpi_reduce_scatter
use mpi,only:mpi_reduce_scatter_init
use mpi,only:mpi_reduce_scatter_block
use mpi,only:mpi_reduce_scatter_block_init
use mpi,only:mpi_register_datarep
use mpi,only:mpi_request_free
use mpi,only:mpi_request_get_status
use mpi,only:mpi_rget
use mpi,only:mpi_rget_accumulate
use mpi,only:mpi_rput
use mpi,only:mpi_rsend
use mpi,only:mpi_rsend_init
use mpi,only:mpi_scan
use mpi,only:mpi_scan_init
use mpi,only:mpi_scatter
use mpi,only:mpi_scatter_init
use mpi,only:mpi_scatterv
use mpi,only:mpi_scatterv_init
use mpi,only:mpi_send
use mpi,only:mpi_send_init
use mpi,only:mpi_sendrecv
use mpi,only:mpi_sendrecv_replace
use mpi,only:mpi_session_call_errhandler
use mpi,only:mpi_session_create_errhandler
use mpi,only:mpi_session_get_errhandler
use mpi,only:mpi_session_finalize
use mpi,only:mpi_session_set_errhandler
use mpi,only:mpi_ssend
use mpi,only:mpi_ssend_init
use mpi,only:mpi_start
use mpi,only:mpi_startall
use mpi,only:mpi_status_set_cancelled
use mpi,only:mpi_status_set_elements
use mpi,only:mpi_status_set_elements_x
use mpi,only:mpi_test
use mpi,only:mpi_test_cancelled
use mpi,only:mpi_testall
use mpi,only:mpi_testany
use mpi,only:mpi_testsome
use mpi,only:mpi_topo_test
use mpi,only:mpi_type_commit
use mpi,only:mpi_type_contiguous
use mpi,only:mpi_type_create_darray
use mpi,only:mpi_type_create_f90_complex
use mpi,only:mpi_type_create_f90_integer
use mpi,only:mpi_type_create_f90_real
use mpi,only:mpi_type_create_hindexed
use mpi,only:mpi_type_create_hindexed_block
use mpi,only:mpi_type_create_hvector
use mpi,only:mpi_type_create_indexed_block
use mpi,only:mpi_type_create_keyval
use mpi,only:mpi_type_create_resized
use mpi,only:mpi_type_create_struct
use mpi,only:mpi_type_create_subarray
use mpi,only:mpi_type_delete_attr
use mpi,only:mpi_type_dup
use mpi,only:mpi_type_free
use mpi,only:mpi_type_free_keyval
use mpi,only:mpi_type_get_attr
use mpi,only:mpi_type_get_contents
use mpi,only:mpi_type_get_envelope
use mpi,only:mpi_type_get_extent
use mpi,only:mpi_type_get_extent_x
use mpi,only:mpi_type_get_name
use mpi,only:mpi_type_get_true_extent
use mpi,only:mpi_type_get_true_extent_x
use mpi,only:mpi_type_indexed
use mpi,only:mpi_type_match_size
use mpi,only:mpi_type_set_attr
use mpi,only:mpi_type_set_name
use mpi,only:mpi_type_size
use mpi,only:mpi_type_size_x
use mpi,only:mpi_type_vector
use mpi,only:mpi_unpack
use mpi,only:mpi_unpack_external
use mpi,only:mpi_unpublish_name
use mpi,only:mpi_wait
use mpi,only:mpi_waitall
use mpi,only:mpi_waitany
use mpi,only:mpi_waitsome
use mpi,only:mpi_win_allocate_cptr
use mpi,only:mpi_win_allocate_shared_cptr
use mpi,only:mpi_win_attach
use mpi,only:mpi_win_call_errhandler
use mpi,only:mpi_win_complete
use mpi,only:mpi_win_create
use mpi,only:mpi_win_create_dynamic
use mpi,only:mpi_win_create_errhandler
use mpi,only:mpi_win_create_keyval
use mpi,only:mpi_win_delete_attr
use mpi,only:mpi_win_detach
use mpi,only:mpi_win_fence
use mpi,only:mpi_win_flush
use mpi,only:mpi_win_flush_all
use mpi,only:mpi_win_flush_local
use mpi,only:mpi_win_flush_local_all
use mpi,only:mpi_win_free
use mpi,only:mpi_win_free_keyval
use mpi,only:mpi_win_get_attr
use mpi,only:mpi_win_get_errhandler
use mpi,only:mpi_win_get_group
use mpi,only:mpi_win_get_info
use mpi,only:mpi_win_get_name
use mpi,only:mpi_win_lock
use mpi,only:mpi_win_lock_all
use mpi,only:mpi_win_post
use mpi,only:mpi_win_set_attr
use mpi,only:mpi_win_set_errhandler
use mpi,only:mpi_win_set_info
use mpi,only:mpi_win_set_name
use mpi,only:mpi_win_shared_query_cptr
use mpi,only:mpi_win_start
use mpi,only:mpi_win_sync
use mpi,only:mpi_win_test
use mpi,only:mpi_win_unlock
use mpi,only:mpi_win_unlock_all
use mpi,only:mpi_win_wait
use mpi,only:mpi_wtick
use mpi,only:mpi_wtime
use mpi,only:mpi_status_f082f
use mpi,only:mpi_status_f2f08
use mpi,only:pmpi_status_f082f
use mpi,only:pmpi_status_f2f08
use mpi,only:pmpi_abort
use mpi,only:pmpi_accumulate
use mpi,only:pmpi_add_error_class
use mpi,only:pmpi_add_error_code
use mpi,only:pmpi_add_error_string
use mpi,only:pmpi_aint_add
use mpi,only:pmpi_aint_diff
use mpi,only:pmpi_allgather
use mpi,only:pmpi_allgather_init
use mpi,only:pmpi_allgatherv
use mpi,only:pmpi_allgatherv_init
use mpi,only:pmpi_alloc_mem_cptr
use mpi,only:pmpi_allreduce
use mpi,only:pmpi_allreduce_init
use mpi,only:pmpi_alltoall
use mpi,only:pmpi_alltoall_init
use mpi,only:pmpi_alltoallv
use mpi,only:pmpi_alltoallv_init
use mpi,only:pmpi_alltoallw
use mpi,only:pmpi_alltoallw_init
use mpi,only:pmpi_barrier
use mpi,only:pmpi_barrier_init
use mpi,only:pmpi_bcast
use mpi,only:pmpi_bcast_init
use mpi,only:pmpi_bsend
use mpi,only:pmpi_bsend_init
use mpi,only:pmpi_buffer_attach
use mpi,only:pmpi_buffer_detach
use mpi,only:pmpi_cancel
use mpi,only:pmpi_cart_coords
use mpi,only:pmpi_cart_create
use mpi,only:pmpi_cart_get
use mpi,only:pmpi_cart_map
use mpi,only:pmpi_cart_rank
use mpi,only:pmpi_cart_shift
use mpi,only:pmpi_cart_sub
use mpi,only:pmpi_cartdim_get
use mpi,only:pmpi_close_port
use mpi,only:pmpi_comm_accept
use mpi,only:pmpi_comm_call_errhandler
use mpi,only:pmpi_comm_compare
use mpi,only:pmpi_comm_connect
use mpi,only:pmpi_comm_create
use mpi,only:pmpi_comm_create_errhandler
use mpi,only:pmpi_comm_create_group
use mpi,only:pmpi_comm_create_keyval
use mpi,only:pmpi_comm_delete_attr
use mpi,only:pmpi_comm_disconnect
use mpi,only:pmpi_comm_dup
use mpi,only:pmpi_comm_dup_with_info
use mpi,only:pmpi_comm_free
use mpi,only:pmpi_comm_free_keyval
use mpi,only:pmpi_comm_get_attr
use mpi,only:pmpi_comm_get_errhandler
use mpi,only:pmpi_comm_get_info
use mpi,only:pmpi_comm_get_name
use mpi,only:pmpi_comm_get_parent
use mpi,only:pmpi_comm_group
use mpi,only:pmpi_comm_idup
use mpi,only:pmpi_comm_idup_with_info
use mpi,only:pmpi_comm_join
use mpi,only:pmpi_comm_rank
use mpi,only:pmpi_comm_remote_group
use mpi,only:pmpi_comm_remote_size
use mpi,only:pmpi_comm_set_attr
use mpi,only:pmpi_comm_set_errhandler
use mpi,only:pmpi_comm_set_info
use mpi,only:pmpi_comm_set_name
use mpi,only:pmpi_comm_size
use mpi,only:pmpi_comm_spawn
use mpi,only:pmpi_comm_spawn_multiple
use mpi,only:pmpi_comm_split
use mpi,only:pmpi_comm_split_type
use mpi,only:pmpi_comm_test_inter
use mpi,only:pmpi_compare_and_swap
use mpi,only:pmpi_dims_create
use mpi,only:pmpi_dist_graph_create
use mpi,only:pmpi_dist_graph_create_adjacent
use mpi,only:pmpi_dist_graph_neighbors
use mpi,only:pmpi_dist_graph_neighbors_count
use mpi,only:pmpi_errhandler_free
use mpi,only:pmpi_error_class
use mpi,only:pmpi_error_string
use mpi,only:pmpi_exscan
use mpi,only:pmpi_exscan_init
use mpi,only:pmpi_f_sync_reg
use mpi,only:pmpi_fetch_and_op
use mpi,only:pmpi_finalize
use mpi,only:pmpi_finalized
use mpi,only:pmpi_free_mem
use mpi,only:pmpi_gather
use mpi,only:pmpi_gather_init
use mpi,only:pmpi_gatherv
use mpi,only:pmpi_gatherv_init
use mpi,only:pmpi_get
use mpi,only:pmpi_get_accumulate
use mpi,only:pmpi_get_address
use mpi,only:pmpi_get_count
use mpi,only:pmpi_get_elements
use mpi,only:pmpi_get_elements_x
use mpi,only:pmpi_get_library_version
use mpi,only:pmpi_get_processor_name
use mpi,only:pmpi_get_version
use mpi,only:pmpi_graph_create
use mpi,only:pmpi_graph_get
use mpi,only:pmpi_graph_map
use mpi,only:pmpi_graph_neighbors
use mpi,only:pmpi_graph_neighbors_count
use mpi,only:pmpi_graphdims_get
use mpi,only:pmpi_grequest_complete
use mpi,only:pmpi_grequest_start
use mpi,only:pmpi_group_compare
use mpi,only:pmpi_group_difference
use mpi,only:pmpi_group_excl
use mpi,only:pmpi_group_free
use mpi,only:pmpi_group_incl
use mpi,only:pmpi_group_intersection
use mpi,only:pmpi_group_range_excl
use mpi,only:pmpi_group_range_incl
use mpi,only:pmpi_group_rank
use mpi,only:pmpi_group_size
use mpi,only:pmpi_group_translate_ranks
use mpi,only:pmpi_group_union
use mpi,only:pmpi_iallgather
use mpi,only:pmpi_iallgatherv
use mpi,only:pmpi_iallreduce
use mpi,only:pmpi_ialltoall
use mpi,only:pmpi_ialltoallv
use mpi,only:pmpi_ialltoallw
use mpi,only:pmpi_ibarrier
use mpi,only:pmpi_ibcast
use mpi,only:pmpi_ibsend
use mpi,only:pmpi_iexscan
use mpi,only:pmpi_igather
use mpi,only:pmpi_igatherv
use mpi,only:pmpi_improbe
use mpi,only:pmpi_imrecv
use mpi,only:pmpi_ineighbor_allgather
use mpi,only:pmpi_ineighbor_allgatherv
use mpi,only:pmpi_ineighbor_alltoall
use mpi,only:pmpi_ineighbor_alltoallv
use mpi,only:pmpi_ineighbor_alltoallw
use mpi,only:pmpi_info_create
use mpi,only:pmpi_info_create_env
use mpi,only:pmpi_info_delete
use mpi,only:pmpi_info_dup
use mpi,only:pmpi_info_free
use mpi,only:pmpi_info_get
use mpi,only:pmpi_info_get_nkeys
use mpi,only:pmpi_info_get_nthkey
use mpi,only:pmpi_info_get_string
use mpi,only:pmpi_info_get_valuelen
use mpi,only:pmpi_info_set
use mpi,only:pmpi_init
use mpi,only:pmpi_init_thread
use mpi,only:pmpi_initialized
use mpi,only:pmpi_intercomm_create
use mpi,only:pmpi_intercomm_merge
use mpi,only:pmpi_iprobe
use mpi,only:pmpi_irecv
use mpi,only:pmpi_ireduce
use mpi,only:pmpi_ireduce_scatter
use mpi,only:pmpi_ireduce_scatter_block
use mpi,only:pmpi_irsend
use mpi,only:pmpi_is_thread_main
use mpi,only:pmpi_iscan
use mpi,only:pmpi_iscatter
use mpi,only:pmpi_iscatterv
use mpi,only:pmpi_isend
use mpi,only:pmpi_isendrecv
use mpi,only:pmpi_isendrecv_replace
use mpi,only:pmpi_issend
use mpi,only:pmpi_psend_init
use mpi,only:pmpi_precv_init
use mpi,only:pmpi_pready
use mpi,only:pmpi_pready_list
use mpi,only:pmpi_pready_range
use mpi,only:pmpi_parrived
use mpi,only:pmpi_lookup_name
use mpi,only:pmpi_mprobe
use mpi,only:pmpi_mrecv
use mpi,only:pmpi_neighbor_allgather
use mpi,only:pmpi_neighbor_allgather_init
use mpi,only:pmpi_neighbor_allgatherv
use mpi,only:pmpi_neighbor_allgatherv_init
use mpi,only:pmpi_neighbor_alltoall
use mpi,only:pmpi_neighbor_alltoall_init
use mpi,only:pmpi_neighbor_alltoallv
use mpi,only:pmpi_neighbor_alltoallv_init
use mpi,only:pmpi_neighbor_alltoallw
use mpi,only:pmpi_neighbor_alltoallw_init
use mpi,only:pmpi_op_commutative
use mpi,only:pmpi_op_create
use mpi,only:pmpi_op_free
use mpi,only:pmpi_open_port
use mpi,only:pmpi_pack
use mpi,only:pmpi_pack_external
use mpi,only:pmpi_pack_external_size
use mpi,only:pmpi_pack_size
use mpi,only:pmpi_pcontrol
use mpi,only:pmpi_probe
use mpi,only:pmpi_publish_name
use mpi,only:pmpi_put
use mpi,only:pmpi_query_thread
use mpi,only:pmpi_raccumulate
use mpi,only:pmpi_recv
use mpi,only:pmpi_recv_init
use mpi,only:pmpi_reduce
use mpi,only:pmpi_reduce_init
use mpi,only:pmpi_reduce_local
use mpi,only:pmpi_reduce_scatter
use mpi,only:pmpi_reduce_scatter_init
use mpi,only:pmpi_reduce_scatter_block
use mpi,only:pmpi_reduce_scatter_block_init
use mpi,only:pmpi_register_datarep
use mpi,only:pmpi_request_free
use mpi,only:pmpi_request_get_status
use mpi,only:pmpi_rget
use mpi,only:pmpi_rget_accumulate
use mpi,only:pmpi_rput
use mpi,only:pmpi_rsend
use mpi,only:pmpi_rsend_init
use mpi,only:pmpi_scan
use mpi,only:pmpi_scan_init
use mpi,only:pmpi_scatter
use mpi,only:pmpi_scatter_init
use mpi,only:pmpi_scatterv
use mpi,only:pmpi_scatterv_init
use mpi,only:pmpi_send
use mpi,only:pmpi_send_init
use mpi,only:pmpi_sendrecv
use mpi,only:pmpi_sendrecv_replace
use mpi,only:pmpi_session_call_errhandler
use mpi,only:pmpi_session_create_errhandler
use mpi,only:pmpi_session_get_errhandler
use mpi,only:pmpi_session_finalize
use mpi,only:pmpi_session_set_errhandler
use mpi,only:pmpi_ssend
use mpi,only:pmpi_ssend_init
use mpi,only:pmpi_start
use mpi,only:pmpi_startall
use mpi,only:pmpi_status_set_cancelled
use mpi,only:pmpi_status_set_elements
use mpi,only:pmpi_status_set_elements_x
use mpi,only:pmpi_test
use mpi,only:pmpi_test_cancelled
use mpi,only:pmpi_testall
use mpi,only:pmpi_testany
use mpi,only:pmpi_testsome
use mpi,only:pmpi_topo_test
use mpi,only:pmpi_type_commit
use mpi,only:pmpi_type_contiguous
use mpi,only:pmpi_type_create_darray
use mpi,only:pmpi_type_create_f90_complex
use mpi,only:pmpi_type_create_f90_integer
use mpi,only:pmpi_type_create_f90_real
use mpi,only:pmpi_type_create_hindexed
use mpi,only:pmpi_type_create_hindexed_block
use mpi,only:pmpi_type_create_hvector
use mpi,only:pmpi_type_create_indexed_block
use mpi,only:pmpi_type_create_keyval
use mpi,only:pmpi_type_create_resized
use mpi,only:pmpi_type_create_struct
use mpi,only:pmpi_type_create_subarray
use mpi,only:pmpi_type_delete_attr
use mpi,only:pmpi_type_dup
use mpi,only:pmpi_type_free
use mpi,only:pmpi_type_free_keyval
use mpi,only:pmpi_type_get_attr
use mpi,only:pmpi_type_get_contents
use mpi,only:pmpi_type_get_envelope
use mpi,only:pmpi_type_get_extent
use mpi,only:pmpi_type_get_extent_x
use mpi,only:pmpi_type_get_name
use mpi,only:pmpi_type_get_true_extent
use mpi,only:pmpi_type_get_true_extent_x
use mpi,only:pmpi_type_indexed
use mpi,only:pmpi_type_match_size
use mpi,only:pmpi_type_set_attr
use mpi,only:pmpi_type_set_name
use mpi,only:pmpi_type_size
use mpi,only:pmpi_type_size_x
use mpi,only:pmpi_type_vector
use mpi,only:pmpi_unpack
use mpi,only:pmpi_unpack_external
use mpi,only:pmpi_unpublish_name
use mpi,only:pmpi_wait
use mpi,only:pmpi_waitall
use mpi,only:pmpi_waitany
use mpi,only:pmpi_waitsome
use mpi,only:pmpi_win_allocate_cptr
use mpi,only:pmpi_win_allocate_shared_cptr
use mpi,only:pmpi_win_attach
use mpi,only:pmpi_win_call_errhandler
use mpi,only:pmpi_win_complete
use mpi,only:pmpi_win_create
use mpi,only:pmpi_win_create_dynamic
use mpi,only:pmpi_win_create_errhandler
use mpi,only:pmpi_win_create_keyval
use mpi,only:pmpi_win_delete_attr
use mpi,only:pmpi_win_detach
use mpi,only:pmpi_win_fence
use mpi,only:pmpi_win_flush
use mpi,only:pmpi_win_flush_all
use mpi,only:pmpi_win_flush_local
use mpi,only:pmpi_win_flush_local_all
use mpi,only:pmpi_win_free
use mpi,only:pmpi_win_free_keyval
use mpi,only:pmpi_win_get_attr
use mpi,only:pmpi_win_get_errhandler
use mpi,only:pmpi_win_get_group
use mpi,only:pmpi_win_get_info
use mpi,only:pmpi_win_get_name
use mpi,only:pmpi_win_lock
use mpi,only:pmpi_win_lock_all
use mpi,only:pmpi_win_post
use mpi,only:pmpi_win_set_attr
use mpi,only:pmpi_win_set_errhandler
use mpi,only:pmpi_win_set_info
use mpi,only:pmpi_win_set_name
use mpi,only:pmpi_win_shared_query_cptr
use mpi,only:pmpi_win_start
use mpi,only:pmpi_win_sync
use mpi,only:pmpi_win_test
use mpi,only:pmpi_win_unlock
use mpi,only:pmpi_win_unlock_all
use mpi,only:pmpi_win_wait
use mpi,only:pmpi_wtick
use mpi,only:pmpi_wtime
use mpi,only:mpi_file_call_errhandler
use mpi,only:mpi_file_close
use mpi,only:mpi_file_create_errhandler
use mpi,only:mpi_file_delete
use mpi,only:mpi_file_get_amode
use mpi,only:mpi_file_get_atomicity
use mpi,only:mpi_file_get_byte_offset
use mpi,only:mpi_file_get_errhandler
use mpi,only:mpi_file_get_group
use mpi,only:mpi_file_get_info
use mpi,only:mpi_file_get_position
use mpi,only:mpi_file_get_position_shared
use mpi,only:mpi_file_get_size
use mpi,only:mpi_file_get_type_extent
use mpi,only:mpi_file_get_view
use mpi,only:mpi_file_iread
use mpi,only:mpi_file_iread_all
use mpi,only:mpi_file_iread_at
use mpi,only:mpi_file_iread_at_all
use mpi,only:mpi_file_iread_shared
use mpi,only:mpi_file_iwrite
use mpi,only:mpi_file_iwrite_all
use mpi,only:mpi_file_iwrite_at
use mpi,only:mpi_file_iwrite_at_all
use mpi,only:mpi_file_iwrite_shared
use mpi,only:mpi_file_open
use mpi,only:mpi_file_preallocate
use mpi,only:mpi_file_read
use mpi,only:mpi_file_read_all
use mpi,only:mpi_file_read_all_begin
use mpi,only:mpi_file_read_all_end
use mpi,only:mpi_file_read_at
use mpi,only:mpi_file_read_at_all
use mpi,only:mpi_file_read_at_all_begin
use mpi,only:mpi_file_read_at_all_end
use mpi,only:mpi_file_read_ordered
use mpi,only:mpi_file_read_ordered_begin
use mpi,only:mpi_file_read_ordered_end
use mpi,only:mpi_file_read_shared
use mpi,only:mpi_file_seek
use mpi,only:mpi_file_seek_shared
use mpi,only:mpi_file_set_atomicity
use mpi,only:mpi_file_set_errhandler
use mpi,only:mpi_file_set_info
use mpi,only:mpi_file_set_size
use mpi,only:mpi_file_set_view
use mpi,only:mpi_file_sync
use mpi,only:mpi_file_write
use mpi,only:mpi_file_write_all
use mpi,only:mpi_file_write_all_begin
use mpi,only:mpi_file_write_all_end
use mpi,only:mpi_file_write_at
use mpi,only:mpi_file_write_at_all
use mpi,only:mpi_file_write_at_all_begin
use mpi,only:mpi_file_write_at_all_end
use mpi,only:mpi_file_write_ordered
use mpi,only:mpi_file_write_ordered_begin
use mpi,only:mpi_file_write_ordered_end
use mpi,only:mpi_file_write_shared
use mpi,only:pmpi_file_call_errhandler
use mpi,only:pmpi_file_close
use mpi,only:pmpi_file_create_errhandler
use mpi,only:pmpi_file_delete
use mpi,only:pmpi_file_get_amode
use mpi,only:pmpi_file_get_atomicity
use mpi,only:pmpi_file_get_byte_offset
use mpi,only:pmpi_file_get_errhandler
use mpi,only:pmpi_file_get_group
use mpi,only:pmpi_file_get_info
use mpi,only:pmpi_file_get_position
use mpi,only:pmpi_file_get_position_shared
use mpi,only:pmpi_file_get_size
use mpi,only:pmpi_file_get_type_extent
use mpi,only:pmpi_file_get_view
use mpi,only:pmpi_file_iread
use mpi,only:pmpi_file_iread_all
use mpi,only:pmpi_file_iread_at
use mpi,only:pmpi_file_iread_at_all
use mpi,only:pmpi_file_iread_shared
use mpi,only:pmpi_file_iwrite
use mpi,only:pmpi_file_iwrite_all
use mpi,only:pmpi_file_iwrite_at
use mpi,only:pmpi_file_iwrite_at_all
use mpi,only:pmpi_file_iwrite_shared
use mpi,only:pmpi_file_open
use mpi,only:pmpi_file_preallocate
use mpi,only:pmpi_file_read
use mpi,only:pmpi_file_read_all
use mpi,only:pmpi_file_read_all_begin
use mpi,only:pmpi_file_read_all_end
use mpi,only:pmpi_file_read_at
use mpi,only:pmpi_file_read_at_all
use mpi,only:pmpi_file_read_at_all_begin
use mpi,only:pmpi_file_read_at_all_end
use mpi,only:pmpi_file_read_ordered
use mpi,only:pmpi_file_read_ordered_begin
use mpi,only:pmpi_file_read_ordered_end
use mpi,only:pmpi_file_read_shared
use mpi,only:pmpi_file_seek
use mpi,only:pmpi_file_seek_shared
use mpi,only:pmpi_file_set_atomicity
use mpi,only:pmpi_file_set_errhandler
use mpi,only:pmpi_file_set_info
use mpi,only:pmpi_file_set_size
use mpi,only:pmpi_file_set_view
use mpi,only:pmpi_file_sync
use mpi,only:pmpi_file_write
use mpi,only:pmpi_file_write_all
use mpi,only:pmpi_file_write_all_begin
use mpi,only:pmpi_file_write_all_end
use mpi,only:pmpi_file_write_at
use mpi,only:pmpi_file_write_at_all
use mpi,only:pmpi_file_write_at_all_begin
use mpi,only:pmpi_file_write_at_all_end
use mpi,only:pmpi_file_write_ordered
use mpi,only:pmpi_file_write_ordered_begin
use mpi,only:pmpi_file_write_ordered_end
use mpi,only:pmpi_file_write_shared
use mpi,only:mpi_sizeof_character_scalar
use mpi,only:mpi_sizeof_character_r1
use mpi,only:mpi_sizeof_character_r2
use mpi,only:mpi_sizeof_character_r3
use mpi,only:mpi_sizeof_character_r4
use mpi,only:mpi_sizeof_character_r5
use mpi,only:mpi_sizeof_character_r6
use mpi,only:mpi_sizeof_character_r7
use mpi,only:mpi_sizeof_character_r8
use mpi,only:mpi_sizeof_character_r9
use mpi,only:mpi_sizeof_character_r10
use mpi,only:mpi_sizeof_character_r11
use mpi,only:mpi_sizeof_character_r12
use mpi,only:mpi_sizeof_character_r13
use mpi,only:mpi_sizeof_character_r14
use mpi,only:mpi_sizeof_character_r15
use mpi,only:mpi_sizeof_complex128_scalar
use mpi,only:mpi_sizeof_complex128_r1
use mpi,only:mpi_sizeof_complex128_r2
use mpi,only:mpi_sizeof_complex128_r3
use mpi,only:mpi_sizeof_complex128_r4
use mpi,only:mpi_sizeof_complex128_r5
use mpi,only:mpi_sizeof_complex128_r6
use mpi,only:mpi_sizeof_complex128_r7
use mpi,only:mpi_sizeof_complex128_r8
use mpi,only:mpi_sizeof_complex128_r9
use mpi,only:mpi_sizeof_complex128_r10
use mpi,only:mpi_sizeof_complex128_r11
use mpi,only:mpi_sizeof_complex128_r12
use mpi,only:mpi_sizeof_complex128_r13
use mpi,only:mpi_sizeof_complex128_r14
use mpi,only:mpi_sizeof_complex128_r15
use mpi,only:mpi_sizeof_complex16_scalar
use mpi,only:mpi_sizeof_complex16_r1
use mpi,only:mpi_sizeof_complex16_r2
use mpi,only:mpi_sizeof_complex16_r3
use mpi,only:mpi_sizeof_complex16_r4
use mpi,only:mpi_sizeof_complex16_r5
use mpi,only:mpi_sizeof_complex16_r6
use mpi,only:mpi_sizeof_complex16_r7
use mpi,only:mpi_sizeof_complex16_r8
use mpi,only:mpi_sizeof_complex16_r9
use mpi,only:mpi_sizeof_complex16_r10
use mpi,only:mpi_sizeof_complex16_r11
use mpi,only:mpi_sizeof_complex16_r12
use mpi,only:mpi_sizeof_complex16_r13
use mpi,only:mpi_sizeof_complex16_r14
use mpi,only:mpi_sizeof_complex16_r15
use mpi,only:mpi_sizeof_complex32_scalar
use mpi,only:mpi_sizeof_complex32_r1
use mpi,only:mpi_sizeof_complex32_r2
use mpi,only:mpi_sizeof_complex32_r3
use mpi,only:mpi_sizeof_complex32_r4
use mpi,only:mpi_sizeof_complex32_r5
use mpi,only:mpi_sizeof_complex32_r6
use mpi,only:mpi_sizeof_complex32_r7
use mpi,only:mpi_sizeof_complex32_r8
use mpi,only:mpi_sizeof_complex32_r9
use mpi,only:mpi_sizeof_complex32_r10
use mpi,only:mpi_sizeof_complex32_r11
use mpi,only:mpi_sizeof_complex32_r12
use mpi,only:mpi_sizeof_complex32_r13
use mpi,only:mpi_sizeof_complex32_r14
use mpi,only:mpi_sizeof_complex32_r15
use mpi,only:mpi_sizeof_complex64_scalar
use mpi,only:mpi_sizeof_complex64_r1
use mpi,only:mpi_sizeof_complex64_r2
use mpi,only:mpi_sizeof_complex64_r3
use mpi,only:mpi_sizeof_complex64_r4
use mpi,only:mpi_sizeof_complex64_r5
use mpi,only:mpi_sizeof_complex64_r6
use mpi,only:mpi_sizeof_complex64_r7
use mpi,only:mpi_sizeof_complex64_r8
use mpi,only:mpi_sizeof_complex64_r9
use mpi,only:mpi_sizeof_complex64_r10
use mpi,only:mpi_sizeof_complex64_r11
use mpi,only:mpi_sizeof_complex64_r12
use mpi,only:mpi_sizeof_complex64_r13
use mpi,only:mpi_sizeof_complex64_r14
use mpi,only:mpi_sizeof_complex64_r15
use mpi,only:mpi_sizeof_int16_scalar
use mpi,only:mpi_sizeof_int16_r1
use mpi,only:mpi_sizeof_int16_r2
use mpi,only:mpi_sizeof_int16_r3
use mpi,only:mpi_sizeof_int16_r4
use mpi,only:mpi_sizeof_int16_r5
use mpi,only:mpi_sizeof_int16_r6
use mpi,only:mpi_sizeof_int16_r7
use mpi,only:mpi_sizeof_int16_r8
use mpi,only:mpi_sizeof_int16_r9
use mpi,only:mpi_sizeof_int16_r10
use mpi,only:mpi_sizeof_int16_r11
use mpi,only:mpi_sizeof_int16_r12
use mpi,only:mpi_sizeof_int16_r13
use mpi,only:mpi_sizeof_int16_r14
use mpi,only:mpi_sizeof_int16_r15
use mpi,only:mpi_sizeof_int32_scalar
use mpi,only:mpi_sizeof_int32_r1
use mpi,only:mpi_sizeof_int32_r2
use mpi,only:mpi_sizeof_int32_r3
use mpi,only:mpi_sizeof_int32_r4
use mpi,only:mpi_sizeof_int32_r5
use mpi,only:mpi_sizeof_int32_r6
use mpi,only:mpi_sizeof_int32_r7
use mpi,only:mpi_sizeof_int32_r8
use mpi,only:mpi_sizeof_int32_r9
use mpi,only:mpi_sizeof_int32_r10
use mpi,only:mpi_sizeof_int32_r11
use mpi,only:mpi_sizeof_int32_r12
use mpi,only:mpi_sizeof_int32_r13
use mpi,only:mpi_sizeof_int32_r14
use mpi,only:mpi_sizeof_int32_r15
use mpi,only:mpi_sizeof_int64_scalar
use mpi,only:mpi_sizeof_int64_r1
use mpi,only:mpi_sizeof_int64_r2
use mpi,only:mpi_sizeof_int64_r3
use mpi,only:mpi_sizeof_int64_r4
use mpi,only:mpi_sizeof_int64_r5
use mpi,only:mpi_sizeof_int64_r6
use mpi,only:mpi_sizeof_int64_r7
use mpi,only:mpi_sizeof_int64_r8
use mpi,only:mpi_sizeof_int64_r9
use mpi,only:mpi_sizeof_int64_r10
use mpi,only:mpi_sizeof_int64_r11
use mpi,only:mpi_sizeof_int64_r12
use mpi,only:mpi_sizeof_int64_r13
use mpi,only:mpi_sizeof_int64_r14
use mpi,only:mpi_sizeof_int64_r15
use mpi,only:mpi_sizeof_int8_scalar
use mpi,only:mpi_sizeof_int8_r1
use mpi,only:mpi_sizeof_int8_r2
use mpi,only:mpi_sizeof_int8_r3
use mpi,only:mpi_sizeof_int8_r4
use mpi,only:mpi_sizeof_int8_r5
use mpi,only:mpi_sizeof_int8_r6
use mpi,only:mpi_sizeof_int8_r7
use mpi,only:mpi_sizeof_int8_r8
use mpi,only:mpi_sizeof_int8_r9
use mpi,only:mpi_sizeof_int8_r10
use mpi,only:mpi_sizeof_int8_r11
use mpi,only:mpi_sizeof_int8_r12
use mpi,only:mpi_sizeof_int8_r13
use mpi,only:mpi_sizeof_int8_r14
use mpi,only:mpi_sizeof_int8_r15
use mpi,only:mpi_sizeof_logical_scalar
use mpi,only:mpi_sizeof_logical_r1
use mpi,only:mpi_sizeof_logical_r2
use mpi,only:mpi_sizeof_logical_r3
use mpi,only:mpi_sizeof_logical_r4
use mpi,only:mpi_sizeof_logical_r5
use mpi,only:mpi_sizeof_logical_r6
use mpi,only:mpi_sizeof_logical_r7
use mpi,only:mpi_sizeof_logical_r8
use mpi,only:mpi_sizeof_logical_r9
use mpi,only:mpi_sizeof_logical_r10
use mpi,only:mpi_sizeof_logical_r11
use mpi,only:mpi_sizeof_logical_r12
use mpi,only:mpi_sizeof_logical_r13
use mpi,only:mpi_sizeof_logical_r14
use mpi,only:mpi_sizeof_logical_r15
use mpi,only:mpi_sizeof_real128_scalar
use mpi,only:mpi_sizeof_real128_r1
use mpi,only:mpi_sizeof_real128_r2
use mpi,only:mpi_sizeof_real128_r3
use mpi,only:mpi_sizeof_real128_r4
use mpi,only:mpi_sizeof_real128_r5
use mpi,only:mpi_sizeof_real128_r6
use mpi,only:mpi_sizeof_real128_r7
use mpi,only:mpi_sizeof_real128_r8
use mpi,only:mpi_sizeof_real128_r9
use mpi,only:mpi_sizeof_real128_r10
use mpi,only:mpi_sizeof_real128_r11
use mpi,only:mpi_sizeof_real128_r12
use mpi,only:mpi_sizeof_real128_r13
use mpi,only:mpi_sizeof_real128_r14
use mpi,only:mpi_sizeof_real128_r15
use mpi,only:mpi_sizeof_real16_scalar
use mpi,only:mpi_sizeof_real16_r1
use mpi,only:mpi_sizeof_real16_r2
use mpi,only:mpi_sizeof_real16_r3
use mpi,only:mpi_sizeof_real16_r4
use mpi,only:mpi_sizeof_real16_r5
use mpi,only:mpi_sizeof_real16_r6
use mpi,only:mpi_sizeof_real16_r7
use mpi,only:mpi_sizeof_real16_r8
use mpi,only:mpi_sizeof_real16_r9
use mpi,only:mpi_sizeof_real16_r10
use mpi,only:mpi_sizeof_real16_r11
use mpi,only:mpi_sizeof_real16_r12
use mpi,only:mpi_sizeof_real16_r13
use mpi,only:mpi_sizeof_real16_r14
use mpi,only:mpi_sizeof_real16_r15
use mpi,only:mpi_sizeof_real32_scalar
use mpi,only:mpi_sizeof_real32_r1
use mpi,only:mpi_sizeof_real32_r2
use mpi,only:mpi_sizeof_real32_r3
use mpi,only:mpi_sizeof_real32_r4
use mpi,only:mpi_sizeof_real32_r5
use mpi,only:mpi_sizeof_real32_r6
use mpi,only:mpi_sizeof_real32_r7
use mpi,only:mpi_sizeof_real32_r8
use mpi,only:mpi_sizeof_real32_r9
use mpi,only:mpi_sizeof_real32_r10
use mpi,only:mpi_sizeof_real32_r11
use mpi,only:mpi_sizeof_real32_r12
use mpi,only:mpi_sizeof_real32_r13
use mpi,only:mpi_sizeof_real32_r14
use mpi,only:mpi_sizeof_real32_r15
use mpi,only:mpi_sizeof_real64_scalar
use mpi,only:mpi_sizeof_real64_r1
use mpi,only:mpi_sizeof_real64_r2
use mpi,only:mpi_sizeof_real64_r3
use mpi,only:mpi_sizeof_real64_r4
use mpi,only:mpi_sizeof_real64_r5
use mpi,only:mpi_sizeof_real64_r6
use mpi,only:mpi_sizeof_real64_r7
use mpi,only:mpi_sizeof_real64_r8
use mpi,only:mpi_sizeof_real64_r9
use mpi,only:mpi_sizeof_real64_r10
use mpi,only:mpi_sizeof_real64_r11
use mpi,only:mpi_sizeof_real64_r12
use mpi,only:mpi_sizeof_real64_r13
use mpi,only:mpi_sizeof_real64_r14
use mpi,only:mpi_sizeof_real64_r15
use mpi,only:pmpi_sizeof_character_scalar
use mpi,only:pmpi_sizeof_character_r1
use mpi,only:pmpi_sizeof_character_r2
use mpi,only:pmpi_sizeof_character_r3
use mpi,only:pmpi_sizeof_character_r4
use mpi,only:pmpi_sizeof_character_r5
use mpi,only:pmpi_sizeof_character_r6
use mpi,only:pmpi_sizeof_character_r7
use mpi,only:pmpi_sizeof_character_r8
use mpi,only:pmpi_sizeof_character_r9
use mpi,only:pmpi_sizeof_character_r10
use mpi,only:pmpi_sizeof_character_r11
use mpi,only:pmpi_sizeof_character_r12
use mpi,only:pmpi_sizeof_character_r13
use mpi,only:pmpi_sizeof_character_r14
use mpi,only:pmpi_sizeof_character_r15
use mpi,only:pmpi_sizeof_complex128_scalar
use mpi,only:pmpi_sizeof_complex128_r1
use mpi,only:pmpi_sizeof_complex128_r2
use mpi,only:pmpi_sizeof_complex128_r3
use mpi,only:pmpi_sizeof_complex128_r4
use mpi,only:pmpi_sizeof_complex128_r5
use mpi,only:pmpi_sizeof_complex128_r6
use mpi,only:pmpi_sizeof_complex128_r7
use mpi,only:pmpi_sizeof_complex128_r8
use mpi,only:pmpi_sizeof_complex128_r9
use mpi,only:pmpi_sizeof_complex128_r10
use mpi,only:pmpi_sizeof_complex128_r11
use mpi,only:pmpi_sizeof_complex128_r12
use mpi,only:pmpi_sizeof_complex128_r13
use mpi,only:pmpi_sizeof_complex128_r14
use mpi,only:pmpi_sizeof_complex128_r15
use mpi,only:pmpi_sizeof_complex16_scalar
use mpi,only:pmpi_sizeof_complex16_r1
use mpi,only:pmpi_sizeof_complex16_r2
use mpi,only:pmpi_sizeof_complex16_r3
use mpi,only:pmpi_sizeof_complex16_r4
use mpi,only:pmpi_sizeof_complex16_r5
use mpi,only:pmpi_sizeof_complex16_r6
use mpi,only:pmpi_sizeof_complex16_r7
use mpi,only:pmpi_sizeof_complex16_r8
use mpi,only:pmpi_sizeof_complex16_r9
use mpi,only:pmpi_sizeof_complex16_r10
use mpi,only:pmpi_sizeof_complex16_r11
use mpi,only:pmpi_sizeof_complex16_r12
use mpi,only:pmpi_sizeof_complex16_r13
use mpi,only:pmpi_sizeof_complex16_r14
use mpi,only:pmpi_sizeof_complex16_r15
use mpi,only:pmpi_sizeof_complex32_scalar
use mpi,only:pmpi_sizeof_complex32_r1
use mpi,only:pmpi_sizeof_complex32_r2
use mpi,only:pmpi_sizeof_complex32_r3
use mpi,only:pmpi_sizeof_complex32_r4
use mpi,only:pmpi_sizeof_complex32_r5
use mpi,only:pmpi_sizeof_complex32_r6
use mpi,only:pmpi_sizeof_complex32_r7
use mpi,only:pmpi_sizeof_complex32_r8
use mpi,only:pmpi_sizeof_complex32_r9
use mpi,only:pmpi_sizeof_complex32_r10
use mpi,only:pmpi_sizeof_complex32_r11
use mpi,only:pmpi_sizeof_complex32_r12
use mpi,only:pmpi_sizeof_complex32_r13
use mpi,only:pmpi_sizeof_complex32_r14
use mpi,only:pmpi_sizeof_complex32_r15
use mpi,only:pmpi_sizeof_complex64_scalar
use mpi,only:pmpi_sizeof_complex64_r1
use mpi,only:pmpi_sizeof_complex64_r2
use mpi,only:pmpi_sizeof_complex64_r3
use mpi,only:pmpi_sizeof_complex64_r4
use mpi,only:pmpi_sizeof_complex64_r5
use mpi,only:pmpi_sizeof_complex64_r6
use mpi,only:pmpi_sizeof_complex64_r7
use mpi,only:pmpi_sizeof_complex64_r8
use mpi,only:pmpi_sizeof_complex64_r9
use mpi,only:pmpi_sizeof_complex64_r10
use mpi,only:pmpi_sizeof_complex64_r11
use mpi,only:pmpi_sizeof_complex64_r12
use mpi,only:pmpi_sizeof_complex64_r13
use mpi,only:pmpi_sizeof_complex64_r14
use mpi,only:pmpi_sizeof_complex64_r15
use mpi,only:pmpi_sizeof_int16_scalar
use mpi,only:pmpi_sizeof_int16_r1
use mpi,only:pmpi_sizeof_int16_r2
use mpi,only:pmpi_sizeof_int16_r3
use mpi,only:pmpi_sizeof_int16_r4
use mpi,only:pmpi_sizeof_int16_r5
use mpi,only:pmpi_sizeof_int16_r6
use mpi,only:pmpi_sizeof_int16_r7
use mpi,only:pmpi_sizeof_int16_r8
use mpi,only:pmpi_sizeof_int16_r9
use mpi,only:pmpi_sizeof_int16_r10
use mpi,only:pmpi_sizeof_int16_r11
use mpi,only:pmpi_sizeof_int16_r12
use mpi,only:pmpi_sizeof_int16_r13
use mpi,only:pmpi_sizeof_int16_r14
use mpi,only:pmpi_sizeof_int16_r15
use mpi,only:pmpi_sizeof_int32_scalar
use mpi,only:pmpi_sizeof_int32_r1
use mpi,only:pmpi_sizeof_int32_r2
use mpi,only:pmpi_sizeof_int32_r3
use mpi,only:pmpi_sizeof_int32_r4
use mpi,only:pmpi_sizeof_int32_r5
use mpi,only:pmpi_sizeof_int32_r6
use mpi,only:pmpi_sizeof_int32_r7
use mpi,only:pmpi_sizeof_int32_r8
use mpi,only:pmpi_sizeof_int32_r9
use mpi,only:pmpi_sizeof_int32_r10
use mpi,only:pmpi_sizeof_int32_r11
use mpi,only:pmpi_sizeof_int32_r12
use mpi,only:pmpi_sizeof_int32_r13
use mpi,only:pmpi_sizeof_int32_r14
use mpi,only:pmpi_sizeof_int32_r15
use mpi,only:pmpi_sizeof_int64_scalar
use mpi,only:pmpi_sizeof_int64_r1
use mpi,only:pmpi_sizeof_int64_r2
use mpi,only:pmpi_sizeof_int64_r3
use mpi,only:pmpi_sizeof_int64_r4
use mpi,only:pmpi_sizeof_int64_r5
use mpi,only:pmpi_sizeof_int64_r6
use mpi,only:pmpi_sizeof_int64_r7
use mpi,only:pmpi_sizeof_int64_r8
use mpi,only:pmpi_sizeof_int64_r9
use mpi,only:pmpi_sizeof_int64_r10
use mpi,only:pmpi_sizeof_int64_r11
use mpi,only:pmpi_sizeof_int64_r12
use mpi,only:pmpi_sizeof_int64_r13
use mpi,only:pmpi_sizeof_int64_r14
use mpi,only:pmpi_sizeof_int64_r15
use mpi,only:pmpi_sizeof_int8_scalar
use mpi,only:pmpi_sizeof_int8_r1
use mpi,only:pmpi_sizeof_int8_r2
use mpi,only:pmpi_sizeof_int8_r3
use mpi,only:pmpi_sizeof_int8_r4
use mpi,only:pmpi_sizeof_int8_r5
use mpi,only:pmpi_sizeof_int8_r6
use mpi,only:pmpi_sizeof_int8_r7
use mpi,only:pmpi_sizeof_int8_r8
use mpi,only:pmpi_sizeof_int8_r9
use mpi,only:pmpi_sizeof_int8_r10
use mpi,only:pmpi_sizeof_int8_r11
use mpi,only:pmpi_sizeof_int8_r12
use mpi,only:pmpi_sizeof_int8_r13
use mpi,only:pmpi_sizeof_int8_r14
use mpi,only:pmpi_sizeof_int8_r15
use mpi,only:pmpi_sizeof_logical_scalar
use mpi,only:pmpi_sizeof_logical_r1
use mpi,only:pmpi_sizeof_logical_r2
use mpi,only:pmpi_sizeof_logical_r3
use mpi,only:pmpi_sizeof_logical_r4
use mpi,only:pmpi_sizeof_logical_r5
use mpi,only:pmpi_sizeof_logical_r6
use mpi,only:pmpi_sizeof_logical_r7
use mpi,only:pmpi_sizeof_logical_r8
use mpi,only:pmpi_sizeof_logical_r9
use mpi,only:pmpi_sizeof_logical_r10
use mpi,only:pmpi_sizeof_logical_r11
use mpi,only:pmpi_sizeof_logical_r12
use mpi,only:pmpi_sizeof_logical_r13
use mpi,only:pmpi_sizeof_logical_r14
use mpi,only:pmpi_sizeof_logical_r15
use mpi,only:pmpi_sizeof_real128_scalar
use mpi,only:pmpi_sizeof_real128_r1
use mpi,only:pmpi_sizeof_real128_r2
use mpi,only:pmpi_sizeof_real128_r3
use mpi,only:pmpi_sizeof_real128_r4
use mpi,only:pmpi_sizeof_real128_r5
use mpi,only:pmpi_sizeof_real128_r6
use mpi,only:pmpi_sizeof_real128_r7
use mpi,only:pmpi_sizeof_real128_r8
use mpi,only:pmpi_sizeof_real128_r9
use mpi,only:pmpi_sizeof_real128_r10
use mpi,only:pmpi_sizeof_real128_r11
use mpi,only:pmpi_sizeof_real128_r12
use mpi,only:pmpi_sizeof_real128_r13
use mpi,only:pmpi_sizeof_real128_r14
use mpi,only:pmpi_sizeof_real128_r15
use mpi,only:pmpi_sizeof_real16_scalar
use mpi,only:pmpi_sizeof_real16_r1
use mpi,only:pmpi_sizeof_real16_r2
use mpi,only:pmpi_sizeof_real16_r3
use mpi,only:pmpi_sizeof_real16_r4
use mpi,only:pmpi_sizeof_real16_r5
use mpi,only:pmpi_sizeof_real16_r6
use mpi,only:pmpi_sizeof_real16_r7
use mpi,only:pmpi_sizeof_real16_r8
use mpi,only:pmpi_sizeof_real16_r9
use mpi,only:pmpi_sizeof_real16_r10
use mpi,only:pmpi_sizeof_real16_r11
use mpi,only:pmpi_sizeof_real16_r12
use mpi,only:pmpi_sizeof_real16_r13
use mpi,only:pmpi_sizeof_real16_r14
use mpi,only:pmpi_sizeof_real16_r15
use mpi,only:pmpi_sizeof_real32_scalar
use mpi,only:pmpi_sizeof_real32_r1
use mpi,only:pmpi_sizeof_real32_r2
use mpi,only:pmpi_sizeof_real32_r3
use mpi,only:pmpi_sizeof_real32_r4
use mpi,only:pmpi_sizeof_real32_r5
use mpi,only:pmpi_sizeof_real32_r6
use mpi,only:pmpi_sizeof_real32_r7
use mpi,only:pmpi_sizeof_real32_r8
use mpi,only:pmpi_sizeof_real32_r9
use mpi,only:pmpi_sizeof_real32_r10
use mpi,only:pmpi_sizeof_real32_r11
use mpi,only:pmpi_sizeof_real32_r12
use mpi,only:pmpi_sizeof_real32_r13
use mpi,only:pmpi_sizeof_real32_r14
use mpi,only:pmpi_sizeof_real32_r15
use mpi,only:pmpi_sizeof_real64_scalar
use mpi,only:pmpi_sizeof_real64_r1
use mpi,only:pmpi_sizeof_real64_r2
use mpi,only:pmpi_sizeof_real64_r3
use mpi,only:pmpi_sizeof_real64_r4
use mpi,only:pmpi_sizeof_real64_r5
use mpi,only:pmpi_sizeof_real64_r6
use mpi,only:pmpi_sizeof_real64_r7
use mpi,only:pmpi_sizeof_real64_r8
use mpi,only:pmpi_sizeof_real64_r9
use mpi,only:pmpi_sizeof_real64_r10
use mpi,only:pmpi_sizeof_real64_r11
use mpi,only:pmpi_sizeof_real64_r12
use mpi,only:pmpi_sizeof_real64_r13
use mpi,only:pmpi_sizeof_real64_r14
use mpi,only:pmpi_sizeof_real64_r15
use mpi,only:mpi_alloc_mem
use mpi,only:mpi_comm_create_from_group
use mpi,only:mpi_group_from_session_pset
use mpi,only:mpi_intercomm_create_from_groups
use mpi,only:mpi_session_get_info
use mpi,only:mpi_session_get_nth_pset
use mpi,only:mpi_session_get_nth_psetlen
use mpi,only:mpi_session_get_pset_info
use mpi,only:mpi_session_init
use mpi,only:mpi_win_allocate
use mpi,only:mpi_win_allocate_shared
use mpi,only:mpi_win_shared_query
use mpi,only:pmpi_alloc_mem
use mpi,only:pmpi_comm_create_from_group
use mpi,only:pmpi_group_from_session_pset
use mpi,only:pmpi_intercomm_create_from_groups
use mpi,only:pmpi_session_get_info
use mpi,only:pmpi_session_get_nth_pset
use mpi,only:pmpi_session_get_nth_psetlen
use mpi,only:pmpi_session_get_pset_info
use mpi,only:pmpi_session_init
use mpi,only:pmpi_win_allocate
use mpi,only:pmpi_win_allocate_shared
use mpi,only:pmpi_win_shared_query
use mpi,only:mpi_sizeof
use mpi,only:pmpi_sizeof
use mpi,only:mpi_bottom
use mpi,only:mpi_in_place
use mpi,only:mpi_argv_null
use mpi,only:mpi_argvs_null
use mpi,only:mpi_errcodes_ignore
use mpi,only:mpi_status_ignore
use mpi,only:mpi_statuses_ignore
use mpi,only:mpi_unweighted
use mpi,only:mpi_weights_empty
use precision,only:c_float
use precision,only:c_double
use precision,only:c_float_complex
use precision,only:c_double_complex
use precision,only:c_int32_t
use precision,only:c_int64_t
use precision,only:c_int
use precision,only:rk8
use precision,only:rk4
use precision,only:ck8
use precision,only:ck4
use precision,only:ik
use precision,only:lik
use aligned_mem,only:c_associated
use aligned_mem,only:c_funloc
use aligned_mem,only:c_funptr
use aligned_mem,only:c_f_pointer
use aligned_mem,only:c_loc
use aligned_mem,only:c_null_funptr
use aligned_mem,only:c_null_ptr
use aligned_mem,only:c_ptr
use aligned_mem,only:c_sizeof
use aligned_mem,only:c_int8_t
use aligned_mem,only:c_int16_t
use aligned_mem,only:c_int128_t
use aligned_mem,only:c_short
use aligned_mem,only:c_long
use aligned_mem,only:c_long_long
use aligned_mem,only:c_signed_char
use aligned_mem,only:c_size_t
use aligned_mem,only:c_intmax_t
use aligned_mem,only:c_intptr_t
use aligned_mem,only:c_ptrdiff_t
use aligned_mem,only:c_int_least8_t
use aligned_mem,only:c_int_fast8_t
use aligned_mem,only:c_int_least16_t
use aligned_mem,only:c_int_fast16_t
use aligned_mem,only:c_int_least32_t
use aligned_mem,only:c_int_fast32_t
use aligned_mem,only:c_int_least64_t
use aligned_mem,only:c_int_fast64_t
use aligned_mem,only:c_int_least128_t
use aligned_mem,only:c_int_fast128_t
use aligned_mem,only:c_long_double
use aligned_mem,only:c_long_double_complex
use aligned_mem,only:c_bool
use aligned_mem,only:c_char
use aligned_mem,only:c_null_char
use aligned_mem,only:c_alert
use aligned_mem,only:c_backspace
use aligned_mem,only:c_form_feed
use aligned_mem,only:c_new_line
use aligned_mem,only:c_carriage_return
use aligned_mem,only:c_horizontal_tab
use aligned_mem,only:c_vertical_tab
use aligned_mem,only:c_float128
use aligned_mem,only:c_float128_complex
use aligned_mem,only:c_uint8_t
use aligned_mem,only:c_uint16_t
use aligned_mem,only:c_uint32_t
use aligned_mem,only:c_uint64_t
use aligned_mem,only:c_uint128_t
use aligned_mem,only:c_unsigned_char
use aligned_mem,only:c_unsigned_short
use aligned_mem,only:c_unsigned
use aligned_mem,only:c_unsigned_long
use aligned_mem,only:c_unsigned_long_long
use aligned_mem,only:c_uintmax_t
use aligned_mem,only:c_uint_fast8_t
use aligned_mem,only:c_uint_fast16_t
use aligned_mem,only:c_uint_fast32_t
use aligned_mem,only:c_uint_fast64_t
use aligned_mem,only:c_uint_fast128_t
use aligned_mem,only:c_uint_least8_t
use aligned_mem,only:c_uint_least16_t
use aligned_mem,only:c_uint_least32_t
use aligned_mem,only:c_uint_least64_t
use aligned_mem,only:c_uint_least128_t
use aligned_mem,only:c_f_procpointer
use aligned_mem,only:posix_memalign
use aligned_mem,only:free
use mpi,only:operator(.eq.)
use,intrinsic::__fortran_builtins,only:operator(.eq.)
use mpi,only:operator(.ne.)
use,intrinsic::__fortran_builtins,only:operator(.ne.)
private::output_unit
private::error_unit
private::pcol
private::prow
private::map_global_array_index_to_local_index
private::local_index
private::least_common_multiple
private::check_alloc
private::check_alloc_cuda_f
private::check_dealloc_cuda_f
private::check_memcpy_cuda_f
private::hh_transform_real
private::elpa_reduce_add_vectors_real
private::elpa_transpose_vectors_real
private::elpa_transpose_vectors_real_double
private::elpa_reduce_add_vectors_real_double
private::solve_tridi_double
private::solve_tridi_double_impl
private::hh_transform_real_double
private::mpi_status
private::mpi_comm
private::mpi_datatype
private::mpi_errhandler
private::mpi_file
private::mpi_group
private::mpi_info
private::mpi_message
private::mpi_op
private::mpi_request
private::mpi_session
private::mpi_win
private::ompi_comm_op_eq
private::ompi_datatype_op_eq
private::ompi_errhandler_op_eq
private::ompi_file_op_eq
private::ompi_group_op_eq
private::ompi_info_op_eq
private::ompi_message_op_eq
private::ompi_op_op_eq
private::ompi_request_op_eq
private::ompi_win_op_eq
private::ompi_comm_op_ne
private::ompi_datatype_op_ne
private::ompi_errhandler_op_ne
private::ompi_file_op_ne
private::ompi_group_op_ne
private::ompi_info_op_ne
private::ompi_message_op_ne
private::ompi_op_op_ne
private::ompi_request_op_ne
private::ompi_win_op_ne
private::ompi_major_version
private::ompi_minor_version
private::ompi_release_version
private::mpi_offset_kind
private::mpi_address_kind
private::mpi_integer_kind
private::mpi_count_kind
private::mpi_status_size
private::mpi_max_processor_name
private::mpi_max_error_string
private::mpi_max_object_name
private::mpi_max_library_version_string
private::mpi_max_info_key
private::mpi_max_info_val
private::mpi_max_port_name
private::mpi_max_datarep_string
private::mpi_max_pset_name_len
private::mpi_max_stringtag_len
private::mpi_subarrays_supported
private::mpi_async_protects_nonblocking
private::mpi_any_source
private::mpi_any_tag
private::mpi_appnum
private::mpi_bsend_overhead
private::mpi_cart
private::mpi_combiner_contiguous
private::mpi_combiner_darray
private::mpi_combiner_dup
private::mpi_combiner_f90_complex
private::mpi_combiner_f90_integer
private::mpi_combiner_f90_real
private::mpi_combiner_hindexed
private::mpi_combiner_hindexed_block
private::mpi_combiner_hindexed_integer
private::mpi_combiner_hvector
private::mpi_combiner_hvector_integer
private::mpi_combiner_indexed
private::mpi_combiner_indexed_block
private::mpi_combiner_named
private::mpi_combiner_resized
private::mpi_combiner_struct
private::mpi_combiner_struct_integer
private::mpi_combiner_subarray
private::mpi_combiner_vector
private::mpi_comm_type_hw_guided
private::mpi_comm_type_hw_unguided
private::mpi_comm_type_shared
private::mpi_congruent
private::mpi_distribute_block
private::mpi_distribute_cyclic
private::mpi_distribute_dflt_darg
private::mpi_distribute_none
private::mpi_dist_graph
private::mpi_error
private::mpi_err_access
private::mpi_err_amode
private::mpi_err_arg
private::mpi_err_assert
private::mpi_err_bad_file
private::mpi_err_base
private::mpi_err_buffer
private::mpi_err_comm
private::mpi_err_conversion
private::mpi_err_count
private::mpi_err_dims
private::mpi_err_disp
private::mpi_err_dup_datarep
private::mpi_err_file
private::mpi_err_file_exists
private::mpi_err_file_in_use
private::mpi_err_group
private::mpi_err_info
private::mpi_err_info_key
private::mpi_err_info_nokey
private::mpi_err_info_value
private::mpi_err_intern
private::mpi_err_in_status
private::mpi_err_io
private::mpi_err_keyval
private::mpi_err_lastcode
private::mpi_err_locktype
private::mpi_err_name
private::mpi_err_not_same
private::mpi_err_no_mem
private::mpi_err_no_space
private::mpi_err_no_such_file
private::mpi_err_op
private::mpi_err_other
private::mpi_err_pending
private::mpi_err_port
private::mpi_err_proc_aborted
private::mpi_err_proc_failed
private::mpi_err_proc_failed_pending
private::mpi_err_quota
private::mpi_err_rank
private::mpi_err_read_only
private::mpi_err_request
private::mpi_err_revoked
private::mpi_err_rma_attach
private::mpi_err_rma_conflict
private::mpi_err_rma_flavor
private::mpi_err_rma_range
private::mpi_err_rma_shared
private::mpi_err_rma_sync
private::mpi_err_root
private::mpi_err_service
private::mpi_err_session
private::mpi_err_size
private::mpi_err_spawn
private::mpi_err_tag
private::mpi_err_topology
private::mpi_err_truncate
private::mpi_err_type
private::mpi_err_unknown
private::mpi_err_unsupported_datarep
private::mpi_err_unsupported_operation
private::mpi_err_value_too_large
private::mpi_err_win
private::mpi_ft
private::mpi_graph
private::mpi_host
private::mpi_ident
private::mpi_io
private::mpi_keyval_invalid
private::mpi_lastusedcode
private::mpi_lock_exclusive
private::mpi_lock_shared
private::mpi_mode_nocheck
private::mpi_mode_noprecede
private::mpi_mode_noput
private::mpi_mode_nostore
private::mpi_mode_nosucceed
private::mpi_order_c
private::mpi_order_fortran
private::mpi_proc_null
private::mpi_root
private::mpi_similar
private::mpi_source
private::mpi_subversion
private::mpi_success
private::mpi_tag
private::mpi_tag_ub
private::mpi_thread_funneled
private::mpi_thread_multiple
private::mpi_thread_serialized
private::mpi_thread_single
private::mpi_typeclass_complex
private::mpi_typeclass_integer
private::mpi_typeclass_real
private::mpi_t_err_cannot_init
private::mpi_t_err_cvar_set_never
private::mpi_t_err_cvar_set_not_now
private::mpi_t_err_invalid
private::mpi_t_err_invalid_handle
private::mpi_t_err_invalid_index
private::mpi_t_err_invalid_item
private::mpi_t_err_invalid_session
private::mpi_t_err_memory
private::mpi_t_err_not_initialized
private::mpi_t_err_out_of_handles
private::mpi_t_err_out_of_sessions
private::mpi_t_err_pvar_no_atomic
private::mpi_t_err_pvar_no_startstop
private::mpi_t_err_pvar_no_write
private::mpi_undefined
private::mpi_unequal
private::mpi_universe_size
private::mpi_version
private::mpi_win_base
private::mpi_win_create_flavor
private::mpi_win_disp_unit
private::mpi_win_flavor_allocate
private::mpi_win_flavor_create
private::mpi_win_flavor_dynamic
private::mpi_win_flavor_shared
private::mpi_win_model
private::mpi_win_separate
private::mpi_win_size
private::mpi_win_unified
private::mpi_wtime_is_global
private::ompi_comm_type_board
private::ompi_comm_type_cluster
private::ompi_comm_type_core
private::ompi_comm_type_cu
private::ompi_comm_type_host
private::ompi_comm_type_hwthread
private::ompi_comm_type_l1cache
private::ompi_comm_type_l2cache
private::ompi_comm_type_l3cache
private::ompi_comm_type_node
private::ompi_comm_type_numa
private::ompi_comm_type_socket
private::mpi_2complex
private::mpi_2double_complex
private::mpi_2double_precision
private::mpi_2int
private::mpi_2integer
private::mpi_2real
private::mpi_aint
private::mpi_band
private::mpi_bor
private::mpi_bxor
private::mpi_byte
private::mpi_char
private::mpi_character
private::mpi_comm_null
private::mpi_comm_self
private::mpi_comm_world
private::mpi_complex
private::mpi_complex16
private::mpi_complex32
private::mpi_complex4
private::mpi_complex8
private::mpi_count
private::mpi_cxx_bool
private::mpi_cxx_complex
private::mpi_cxx_double_complex
private::mpi_cxx_float_complex
private::mpi_cxx_long_double_complex
private::mpi_c_bool
private::mpi_c_complex
private::mpi_c_double_complex
private::mpi_c_float_complex
private::mpi_c_long_double_complex
private::mpi_datatype_null
private::mpi_double
private::mpi_double_complex
private::mpi_double_int
private::mpi_double_precision
private::mpi_errhandler_null
private::mpi_errors_abort
private::mpi_errors_are_fatal
private::mpi_errors_return
private::mpi_float
private::mpi_float_int
private::mpi_group_empty
private::mpi_group_null
private::mpi_info_env
private::mpi_info_null
private::mpi_int
private::mpi_int16_t
private::mpi_int32_t
private::mpi_int64_t
private::mpi_int8_t
private::mpi_integer
private::mpi_integer1
private::mpi_integer16
private::mpi_integer2
private::mpi_integer4
private::mpi_integer8
private::mpi_land
private::mpi_lb
private::mpi_logical
private::mpi_logical1
private::mpi_logical2
private::mpi_logical4
private::mpi_logical8
private::mpi_long
private::mpi_long_double
private::mpi_long_double_int
private::mpi_long_int
private::mpi_long_long
private::mpi_long_long_int
private::mpi_lor
private::mpi_lxor
private::mpi_max
private::mpi_maxloc
private::mpi_message_no_proc
private::mpi_message_null
private::mpi_min
private::mpi_minloc
private::mpi_no_op
private::mpi_offset
private::mpi_op_null
private::mpi_packed
private::mpi_prod
private::mpi_real
private::mpi_real16
private::mpi_real2
private::mpi_real4
private::mpi_real8
private::mpi_replace
private::mpi_request_null
private::mpi_session_null
private::mpi_short
private::mpi_short_int
private::mpi_signed_char
private::mpi_sum
private::mpi_ub
private::mpi_uint16_t
private::mpi_uint32_t
private::mpi_uint64_t
private::mpi_uint8_t
private::mpi_unsigned
private::mpi_unsigned_char
private::mpi_unsigned_long
private::mpi_unsigned_long_long
private::mpi_unsigned_short
private::mpi_wchar
private::mpi_win_null
private::mpi_mode_append
private::mpi_mode_create
private::mpi_mode_delete_on_close
private::mpi_mode_excl
private::mpi_mode_rdonly
private::mpi_mode_rdwr
private::mpi_mode_sequential
private::mpi_mode_unique_open
private::mpi_mode_wronly
private::mpi_seek_cur
private::mpi_seek_end
private::mpi_seek_set
private::mpi_displacement_current
private::mpi_file_null
private::mpi_dup_fn
private::mpi_null_copy_fn
private::mpi_null_delete_fn
private::mpi_comm_dup_fn
private::mpi_comm_null_copy_fn
private::mpi_comm_null_delete_fn
private::mpi_type_dup_fn
private::mpi_type_null_copy_fn
private::mpi_type_null_delete_fn
private::mpi_win_dup_fn
private::mpi_win_null_copy_fn
private::mpi_win_null_delete_fn
private::mpi_conversion_fn_null
private::mpi_abort
private::mpi_accumulate
private::mpi_add_error_class
private::mpi_add_error_code
private::mpi_add_error_string
private::mpi_aint_add
private::mpi_aint_diff
private::mpi_allgather
private::mpi_allgather_init
private::mpi_allgatherv
private::mpi_allgatherv_init
private::mpi_alloc_mem_cptr
private::mpi_allreduce
private::mpi_allreduce_init
private::mpi_alltoall
private::mpi_alltoall_init
private::mpi_alltoallv
private::mpi_alltoallv_init
private::mpi_alltoallw
private::mpi_alltoallw_init
private::mpi_barrier
private::mpi_barrier_init
private::mpi_bcast
private::mpi_bcast_init
private::mpi_bsend
private::mpi_bsend_init
private::mpi_buffer_attach
private::mpi_buffer_detach
private::mpi_cancel
private::mpi_cart_coords
private::mpi_cart_create
private::mpi_cart_get
private::mpi_cart_map
private::mpi_cart_rank
private::mpi_cart_shift
private::mpi_cart_sub
private::mpi_cartdim_get
private::mpi_close_port
private::mpi_comm_accept
private::mpi_comm_call_errhandler
private::mpi_comm_compare
private::mpi_comm_connect
private::mpi_comm_create
private::mpi_comm_create_errhandler
private::mpi_comm_create_group
private::mpi_comm_create_keyval
private::mpi_comm_delete_attr
private::mpi_comm_disconnect
private::mpi_comm_dup
private::mpi_comm_dup_with_info
private::mpi_comm_free
private::mpi_comm_free_keyval
private::mpi_comm_get_attr
private::mpi_comm_get_errhandler
private::mpi_comm_get_info
private::mpi_comm_get_name
private::mpi_comm_get_parent
private::mpi_comm_group
private::mpi_comm_idup
private::mpi_comm_idup_with_info
private::mpi_comm_join
private::mpi_comm_rank
private::mpi_comm_remote_group
private::mpi_comm_remote_size
private::mpi_comm_set_attr
private::mpi_comm_set_errhandler
private::mpi_comm_set_info
private::mpi_comm_set_name
private::mpi_comm_size
private::mpi_comm_spawn
private::mpi_comm_spawn_multiple
private::mpi_comm_split
private::mpi_comm_split_type
private::mpi_comm_test_inter
private::mpi_compare_and_swap
private::mpi_dims_create
private::mpi_dist_graph_create
private::mpi_dist_graph_create_adjacent
private::mpi_dist_graph_neighbors
private::mpi_dist_graph_neighbors_count
private::mpi_errhandler_free
private::mpi_error_class
private::mpi_error_string
private::mpi_exscan
private::mpi_exscan_init
private::mpi_f_sync_reg
private::mpi_fetch_and_op
private::mpi_finalize
private::mpi_finalized
private::mpi_free_mem
private::mpi_gather
private::mpi_gather_init
private::mpi_gatherv
private::mpi_gatherv_init
private::mpi_get
private::mpi_get_accumulate
private::mpi_get_address
private::mpi_get_count
private::mpi_get_elements
private::mpi_get_elements_x
private::mpi_get_library_version
private::mpi_get_processor_name
private::mpi_get_version
private::mpi_graph_create
private::mpi_graph_get
private::mpi_graph_map
private::mpi_graph_neighbors
private::mpi_graph_neighbors_count
private::mpi_graphdims_get
private::mpi_grequest_complete
private::mpi_grequest_start
private::mpi_group_compare
private::mpi_group_difference
private::mpi_group_excl
private::mpi_group_free
private::mpi_group_incl
private::mpi_group_intersection
private::mpi_group_range_excl
private::mpi_group_range_incl
private::mpi_group_rank
private::mpi_group_size
private::mpi_group_translate_ranks
private::mpi_group_union
private::mpi_iallgather
private::mpi_iallgatherv
private::mpi_iallreduce
private::mpi_ialltoall
private::mpi_ialltoallv
private::mpi_ialltoallw
private::mpi_ibarrier
private::mpi_ibcast
private::mpi_ibsend
private::mpi_iexscan
private::mpi_igather
private::mpi_igatherv
private::mpi_improbe
private::mpi_imrecv
private::mpi_ineighbor_allgather
private::mpi_ineighbor_allgatherv
private::mpi_ineighbor_alltoall
private::mpi_ineighbor_alltoallv
private::mpi_ineighbor_alltoallw
private::mpi_info_create
private::mpi_info_create_env
private::mpi_info_delete
private::mpi_info_dup
private::mpi_info_free
private::mpi_info_get
private::mpi_info_get_nkeys
private::mpi_info_get_nthkey
private::mpi_info_get_string
private::mpi_info_get_valuelen
private::mpi_info_set
private::mpi_init
private::mpi_init_thread
private::mpi_initialized
private::mpi_intercomm_create
private::mpi_intercomm_merge
private::mpi_iprobe
private::mpi_irecv
private::mpi_ireduce
private::mpi_ireduce_scatter
private::mpi_ireduce_scatter_block
private::mpi_irsend
private::mpi_is_thread_main
private::mpi_iscan
private::mpi_iscatter
private::mpi_iscatterv
private::mpi_isend
private::mpi_isendrecv
private::mpi_isendrecv_replace
private::mpi_issend
private::mpi_psend_init
private::mpi_precv_init
private::mpi_pready
private::mpi_pready_list
private::mpi_pready_range
private::mpi_parrived
private::mpi_lookup_name
private::mpi_mprobe
private::mpi_mrecv
private::mpi_neighbor_allgather
private::mpi_neighbor_allgather_init
private::mpi_neighbor_allgatherv
private::mpi_neighbor_allgatherv_init
private::mpi_neighbor_alltoall
private::mpi_neighbor_alltoall_init
private::mpi_neighbor_alltoallv
private::mpi_neighbor_alltoallv_init
private::mpi_neighbor_alltoallw
private::mpi_neighbor_alltoallw_init
private::mpi_op_commutative
private::mpi_op_create
private::mpi_op_free
private::mpi_open_port
private::mpi_pack
private::mpi_pack_external
private::mpi_pack_external_size
private::mpi_pack_size
private::mpi_pcontrol
private::mpi_probe
private::mpi_publish_name
private::mpi_put
private::mpi_query_thread
private::mpi_raccumulate
private::mpi_recv
private::mpi_recv_init
private::mpi_reduce
private::mpi_reduce_init
private::mpi_reduce_local
private::mpi_reduce_scatter
private::mpi_reduce_scatter_init
private::mpi_reduce_scatter_block
private::mpi_reduce_scatter_block_init
private::mpi_register_datarep
private::mpi_request_free
private::mpi_request_get_status
private::mpi_rget
private::mpi_rget_accumulate
private::mpi_rput
private::mpi_rsend
private::mpi_rsend_init
private::mpi_scan
private::mpi_scan_init
private::mpi_scatter
private::mpi_scatter_init
private::mpi_scatterv
private::mpi_scatterv_init
private::mpi_send
private::mpi_send_init
private::mpi_sendrecv
private::mpi_sendrecv_replace
private::mpi_session_call_errhandler
private::mpi_session_create_errhandler
private::mpi_session_get_errhandler
private::mpi_session_finalize
private::mpi_session_set_errhandler
private::mpi_ssend
private::mpi_ssend_init
private::mpi_start
private::mpi_startall
private::mpi_status_set_cancelled
private::mpi_status_set_elements
private::mpi_status_set_elements_x
private::mpi_test
private::mpi_test_cancelled
private::mpi_testall
private::mpi_testany
private::mpi_testsome
private::mpi_topo_test
private::mpi_type_commit
private::mpi_type_contiguous
private::mpi_type_create_darray
private::mpi_type_create_f90_complex
private::mpi_type_create_f90_integer
private::mpi_type_create_f90_real
private::mpi_type_create_hindexed
private::mpi_type_create_hindexed_block
private::mpi_type_create_hvector
private::mpi_type_create_indexed_block
private::mpi_type_create_keyval
private::mpi_type_create_resized
private::mpi_type_create_struct
private::mpi_type_create_subarray
private::mpi_type_delete_attr
private::mpi_type_dup
private::mpi_type_free
private::mpi_type_free_keyval
private::mpi_type_get_attr
private::mpi_type_get_contents
private::mpi_type_get_envelope
private::mpi_type_get_extent
private::mpi_type_get_extent_x
private::mpi_type_get_name
private::mpi_type_get_true_extent
private::mpi_type_get_true_extent_x
private::mpi_type_indexed
private::mpi_type_match_size
private::mpi_type_set_attr
private::mpi_type_set_name
private::mpi_type_size
private::mpi_type_size_x
private::mpi_type_vector
private::mpi_unpack
private::mpi_unpack_external
private::mpi_unpublish_name
private::mpi_wait
private::mpi_waitall
private::mpi_waitany
private::mpi_waitsome
private::mpi_win_allocate_cptr
private::mpi_win_allocate_shared_cptr
private::mpi_win_attach
private::mpi_win_call_errhandler
private::mpi_win_complete
private::mpi_win_create
private::mpi_win_create_dynamic
private::mpi_win_create_errhandler
private::mpi_win_create_keyval
private::mpi_win_delete_attr
private::mpi_win_detach
private::mpi_win_fence
private::mpi_win_flush
private::mpi_win_flush_all
private::mpi_win_flush_local
private::mpi_win_flush_local_all
private::mpi_win_free
private::mpi_win_free_keyval
private::mpi_win_get_attr
private::mpi_win_get_errhandler
private::mpi_win_get_group
private::mpi_win_get_info
private::mpi_win_get_name
private::mpi_win_lock
private::mpi_win_lock_all
private::mpi_win_post
private::mpi_win_set_attr
private::mpi_win_set_errhandler
private::mpi_win_set_info
private::mpi_win_set_name
private::mpi_win_shared_query_cptr
private::mpi_win_start
private::mpi_win_sync
private::mpi_win_test
private::mpi_win_unlock
private::mpi_win_unlock_all
private::mpi_win_wait
private::mpi_wtick
private::mpi_wtime
private::mpi_status_f082f
private::mpi_status_f2f08
private::pmpi_status_f082f
private::pmpi_status_f2f08
private::pmpi_abort
private::pmpi_accumulate
private::pmpi_add_error_class
private::pmpi_add_error_code
private::pmpi_add_error_string
private::pmpi_aint_add
private::pmpi_aint_diff
private::pmpi_allgather
private::pmpi_allgather_init
private::pmpi_allgatherv
private::pmpi_allgatherv_init
private::pmpi_alloc_mem_cptr
private::pmpi_allreduce
private::pmpi_allreduce_init
private::pmpi_alltoall
private::pmpi_alltoall_init
private::pmpi_alltoallv
private::pmpi_alltoallv_init
private::pmpi_alltoallw
private::pmpi_alltoallw_init
private::pmpi_barrier
private::pmpi_barrier_init
private::pmpi_bcast
private::pmpi_bcast_init
private::pmpi_bsend
private::pmpi_bsend_init
private::pmpi_buffer_attach
private::pmpi_buffer_detach
private::pmpi_cancel
private::pmpi_cart_coords
private::pmpi_cart_create
private::pmpi_cart_get
private::pmpi_cart_map
private::pmpi_cart_rank
private::pmpi_cart_shift
private::pmpi_cart_sub
private::pmpi_cartdim_get
private::pmpi_close_port
private::pmpi_comm_accept
private::pmpi_comm_call_errhandler
private::pmpi_comm_compare
private::pmpi_comm_connect
private::pmpi_comm_create
private::pmpi_comm_create_errhandler
private::pmpi_comm_create_group
private::pmpi_comm_create_keyval
private::pmpi_comm_delete_attr
private::pmpi_comm_disconnect
private::pmpi_comm_dup
private::pmpi_comm_dup_with_info
private::pmpi_comm_free
private::pmpi_comm_free_keyval
private::pmpi_comm_get_attr
private::pmpi_comm_get_errhandler
private::pmpi_comm_get_info
private::pmpi_comm_get_name
private::pmpi_comm_get_parent
private::pmpi_comm_group
private::pmpi_comm_idup
private::pmpi_comm_idup_with_info
private::pmpi_comm_join
private::pmpi_comm_rank
private::pmpi_comm_remote_group
private::pmpi_comm_remote_size
private::pmpi_comm_set_attr
private::pmpi_comm_set_errhandler
private::pmpi_comm_set_info
private::pmpi_comm_set_name
private::pmpi_comm_size
private::pmpi_comm_spawn
private::pmpi_comm_spawn_multiple
private::pmpi_comm_split
private::pmpi_comm_split_type
private::pmpi_comm_test_inter
private::pmpi_compare_and_swap
private::pmpi_dims_create
private::pmpi_dist_graph_create
private::pmpi_dist_graph_create_adjacent
private::pmpi_dist_graph_neighbors
private::pmpi_dist_graph_neighbors_count
private::pmpi_errhandler_free
private::pmpi_error_class
private::pmpi_error_string
private::pmpi_exscan
private::pmpi_exscan_init
private::pmpi_f_sync_reg
private::pmpi_fetch_and_op
private::pmpi_finalize
private::pmpi_finalized
private::pmpi_free_mem
private::pmpi_gather
private::pmpi_gather_init
private::pmpi_gatherv
private::pmpi_gatherv_init
private::pmpi_get
private::pmpi_get_accumulate
private::pmpi_get_address
private::pmpi_get_count
private::pmpi_get_elements
private::pmpi_get_elements_x
private::pmpi_get_library_version
private::pmpi_get_processor_name
private::pmpi_get_version
private::pmpi_graph_create
private::pmpi_graph_get
private::pmpi_graph_map
private::pmpi_graph_neighbors
private::pmpi_graph_neighbors_count
private::pmpi_graphdims_get
private::pmpi_grequest_complete
private::pmpi_grequest_start
private::pmpi_group_compare
private::pmpi_group_difference
private::pmpi_group_excl
private::pmpi_group_free
private::pmpi_group_incl
private::pmpi_group_intersection
private::pmpi_group_range_excl
private::pmpi_group_range_incl
private::pmpi_group_rank
private::pmpi_group_size
private::pmpi_group_translate_ranks
private::pmpi_group_union
private::pmpi_iallgather
private::pmpi_iallgatherv
private::pmpi_iallreduce
private::pmpi_ialltoall
private::pmpi_ialltoallv
private::pmpi_ialltoallw
private::pmpi_ibarrier
private::pmpi_ibcast
private::pmpi_ibsend
private::pmpi_iexscan
private::pmpi_igather
private::pmpi_igatherv
private::pmpi_improbe
private::pmpi_imrecv
private::pmpi_ineighbor_allgather
private::pmpi_ineighbor_allgatherv
private::pmpi_ineighbor_alltoall
private::pmpi_ineighbor_alltoallv
private::pmpi_ineighbor_alltoallw
private::pmpi_info_create
private::pmpi_info_create_env
private::pmpi_info_delete
private::pmpi_info_dup
private::pmpi_info_free
private::pmpi_info_get
private::pmpi_info_get_nkeys
private::pmpi_info_get_nthkey
private::pmpi_info_get_string
private::pmpi_info_get_valuelen
private::pmpi_info_set
private::pmpi_init
private::pmpi_init_thread
private::pmpi_initialized
private::pmpi_intercomm_create
private::pmpi_intercomm_merge
private::pmpi_iprobe
private::pmpi_irecv
private::pmpi_ireduce
private::pmpi_ireduce_scatter
private::pmpi_ireduce_scatter_block
private::pmpi_irsend
private::pmpi_is_thread_main
private::pmpi_iscan
private::pmpi_iscatter
private::pmpi_iscatterv
private::pmpi_isend
private::pmpi_isendrecv
private::pmpi_isendrecv_replace
private::pmpi_issend
private::pmpi_psend_init
private::pmpi_precv_init
private::pmpi_pready
private::pmpi_pready_list
private::pmpi_pready_range
private::pmpi_parrived
private::pmpi_lookup_name
private::pmpi_mprobe
private::pmpi_mrecv
private::pmpi_neighbor_allgather
private::pmpi_neighbor_allgather_init
private::pmpi_neighbor_allgatherv
private::pmpi_neighbor_allgatherv_init
private::pmpi_neighbor_alltoall
private::pmpi_neighbor_alltoall_init
private::pmpi_neighbor_alltoallv
private::pmpi_neighbor_alltoallv_init
private::pmpi_neighbor_alltoallw
private::pmpi_neighbor_alltoallw_init
private::pmpi_op_commutative
private::pmpi_op_create
private::pmpi_op_free
private::pmpi_open_port
private::pmpi_pack
private::pmpi_pack_external
private::pmpi_pack_external_size
private::pmpi_pack_size
private::pmpi_pcontrol
private::pmpi_probe
private::pmpi_publish_name
private::pmpi_put
private::pmpi_query_thread
private::pmpi_raccumulate
private::pmpi_recv
private::pmpi_recv_init
private::pmpi_reduce
private::pmpi_reduce_init
private::pmpi_reduce_local
private::pmpi_reduce_scatter
private::pmpi_reduce_scatter_init
private::pmpi_reduce_scatter_block
private::pmpi_reduce_scatter_block_init
private::pmpi_register_datarep
private::pmpi_request_free
private::pmpi_request_get_status
private::pmpi_rget
private::pmpi_rget_accumulate
private::pmpi_rput
private::pmpi_rsend
private::pmpi_rsend_init
private::pmpi_scan
private::pmpi_scan_init
private::pmpi_scatter
private::pmpi_scatter_init
private::pmpi_scatterv
private::pmpi_scatterv_init
private::pmpi_send
private::pmpi_send_init
private::pmpi_sendrecv
private::pmpi_sendrecv_replace
private::pmpi_session_call_errhandler
private::pmpi_session_create_errhandler
private::pmpi_session_get_errhandler
private::pmpi_session_finalize
private::pmpi_session_set_errhandler
private::pmpi_ssend
private::pmpi_ssend_init
private::pmpi_start
private::pmpi_startall
private::pmpi_status_set_cancelled
private::pmpi_status_set_elements
private::pmpi_status_set_elements_x
private::pmpi_test
private::pmpi_test_cancelled
private::pmpi_testall
private::pmpi_testany
private::pmpi_testsome
private::pmpi_topo_test
private::pmpi_type_commit
private::pmpi_type_contiguous
private::pmpi_type_create_darray
private::pmpi_type_create_f90_complex
private::pmpi_type_create_f90_integer
private::pmpi_type_create_f90_real
private::pmpi_type_create_hindexed
private::pmpi_type_create_hindexed_block
private::pmpi_type_create_hvector
private::pmpi_type_create_indexed_block
private::pmpi_type_create_keyval
private::pmpi_type_create_resized
private::pmpi_type_create_struct
private::pmpi_type_create_subarray
private::pmpi_type_delete_attr
private::pmpi_type_dup
private::pmpi_type_free
private::pmpi_type_free_keyval
private::pmpi_type_get_attr
private::pmpi_type_get_contents
private::pmpi_type_get_envelope
private::pmpi_type_get_extent
private::pmpi_type_get_extent_x
private::pmpi_type_get_name
private::pmpi_type_get_true_extent
private::pmpi_type_get_true_extent_x
private::pmpi_type_indexed
private::pmpi_type_match_size
private::pmpi_type_set_attr
private::pmpi_type_set_name
private::pmpi_type_size
private::pmpi_type_size_x
private::pmpi_type_vector
private::pmpi_unpack
private::pmpi_unpack_external
private::pmpi_unpublish_name
private::pmpi_wait
private::pmpi_waitall
private::pmpi_waitany
private::pmpi_waitsome
private::pmpi_win_allocate_cptr
private::pmpi_win_allocate_shared_cptr
private::pmpi_win_attach
private::pmpi_win_call_errhandler
private::pmpi_win_complete
private::pmpi_win_create
private::pmpi_win_create_dynamic
private::pmpi_win_create_errhandler
private::pmpi_win_create_keyval
private::pmpi_win_delete_attr
private::pmpi_win_detach
private::pmpi_win_fence
private::pmpi_win_flush
private::pmpi_win_flush_all
private::pmpi_win_flush_local
private::pmpi_win_flush_local_all
private::pmpi_win_free
private::pmpi_win_free_keyval
private::pmpi_win_get_attr
private::pmpi_win_get_errhandler
private::pmpi_win_get_group
private::pmpi_win_get_info
private::pmpi_win_get_name
private::pmpi_win_lock
private::pmpi_win_lock_all
private::pmpi_win_post
private::pmpi_win_set_attr
private::pmpi_win_set_errhandler
private::pmpi_win_set_info
private::pmpi_win_set_name
private::pmpi_win_shared_query_cptr
private::pmpi_win_start
private::pmpi_win_sync
private::pmpi_win_test
private::pmpi_win_unlock
private::pmpi_win_unlock_all
private::pmpi_win_wait
private::pmpi_wtick
private::pmpi_wtime
private::mpi_file_call_errhandler
private::mpi_file_close
private::mpi_file_create_errhandler
private::mpi_file_delete
private::mpi_file_get_amode
private::mpi_file_get_atomicity
private::mpi_file_get_byte_offset
private::mpi_file_get_errhandler
private::mpi_file_get_group
private::mpi_file_get_info
private::mpi_file_get_position
private::mpi_file_get_position_shared
private::mpi_file_get_size
private::mpi_file_get_type_extent
private::mpi_file_get_view
private::mpi_file_iread
private::mpi_file_iread_all
private::mpi_file_iread_at
private::mpi_file_iread_at_all
private::mpi_file_iread_shared
private::mpi_file_iwrite
private::mpi_file_iwrite_all
private::mpi_file_iwrite_at
private::mpi_file_iwrite_at_all
private::mpi_file_iwrite_shared
private::mpi_file_open
private::mpi_file_preallocate
private::mpi_file_read
private::mpi_file_read_all
private::mpi_file_read_all_begin
private::mpi_file_read_all_end
private::mpi_file_read_at
private::mpi_file_read_at_all
private::mpi_file_read_at_all_begin
private::mpi_file_read_at_all_end
private::mpi_file_read_ordered
private::mpi_file_read_ordered_begin
private::mpi_file_read_ordered_end
private::mpi_file_read_shared
private::mpi_file_seek
private::mpi_file_seek_shared
private::mpi_file_set_atomicity
private::mpi_file_set_errhandler
private::mpi_file_set_info
private::mpi_file_set_size
private::mpi_file_set_view
private::mpi_file_sync
private::mpi_file_write
private::mpi_file_write_all
private::mpi_file_write_all_begin
private::mpi_file_write_all_end
private::mpi_file_write_at
private::mpi_file_write_at_all
private::mpi_file_write_at_all_begin
private::mpi_file_write_at_all_end
private::mpi_file_write_ordered
private::mpi_file_write_ordered_begin
private::mpi_file_write_ordered_end
private::mpi_file_write_shared
private::pmpi_file_call_errhandler
private::pmpi_file_close
private::pmpi_file_create_errhandler
private::pmpi_file_delete
private::pmpi_file_get_amode
private::pmpi_file_get_atomicity
private::pmpi_file_get_byte_offset
private::pmpi_file_get_errhandler
private::pmpi_file_get_group
private::pmpi_file_get_info
private::pmpi_file_get_position
private::pmpi_file_get_position_shared
private::pmpi_file_get_size
private::pmpi_file_get_type_extent
private::pmpi_file_get_view
private::pmpi_file_iread
private::pmpi_file_iread_all
private::pmpi_file_iread_at
private::pmpi_file_iread_at_all
private::pmpi_file_iread_shared
private::pmpi_file_iwrite
private::pmpi_file_iwrite_all
private::pmpi_file_iwrite_at
private::pmpi_file_iwrite_at_all
private::pmpi_file_iwrite_shared
private::pmpi_file_open
private::pmpi_file_preallocate
private::pmpi_file_read
private::pmpi_file_read_all
private::pmpi_file_read_all_begin
private::pmpi_file_read_all_end
private::pmpi_file_read_at
private::pmpi_file_read_at_all
private::pmpi_file_read_at_all_begin
private::pmpi_file_read_at_all_end
private::pmpi_file_read_ordered
private::pmpi_file_read_ordered_begin
private::pmpi_file_read_ordered_end
private::pmpi_file_read_shared
private::pmpi_file_seek
private::pmpi_file_seek_shared
private::pmpi_file_set_atomicity
private::pmpi_file_set_errhandler
private::pmpi_file_set_info
private::pmpi_file_set_size
private::pmpi_file_set_view
private::pmpi_file_sync
private::pmpi_file_write
private::pmpi_file_write_all
private::pmpi_file_write_all_begin
private::pmpi_file_write_all_end
private::pmpi_file_write_at
private::pmpi_file_write_at_all
private::pmpi_file_write_at_all_begin
private::pmpi_file_write_at_all_end
private::pmpi_file_write_ordered
private::pmpi_file_write_ordered_begin
private::pmpi_file_write_ordered_end
private::pmpi_file_write_shared
private::mpi_sizeof_character_scalar
private::mpi_sizeof_character_r1
private::mpi_sizeof_character_r2
private::mpi_sizeof_character_r3
private::mpi_sizeof_character_r4
private::mpi_sizeof_character_r5
private::mpi_sizeof_character_r6
private::mpi_sizeof_character_r7
private::mpi_sizeof_character_r8
private::mpi_sizeof_character_r9
private::mpi_sizeof_character_r10
private::mpi_sizeof_character_r11
private::mpi_sizeof_character_r12
private::mpi_sizeof_character_r13
private::mpi_sizeof_character_r14
private::mpi_sizeof_character_r15
private::mpi_sizeof_complex128_scalar
private::mpi_sizeof_complex128_r1
private::mpi_sizeof_complex128_r2
private::mpi_sizeof_complex128_r3
private::mpi_sizeof_complex128_r4
private::mpi_sizeof_complex128_r5
private::mpi_sizeof_complex128_r6
private::mpi_sizeof_complex128_r7
private::mpi_sizeof_complex128_r8
private::mpi_sizeof_complex128_r9
private::mpi_sizeof_complex128_r10
private::mpi_sizeof_complex128_r11
private::mpi_sizeof_complex128_r12
private::mpi_sizeof_complex128_r13
private::mpi_sizeof_complex128_r14
private::mpi_sizeof_complex128_r15
private::mpi_sizeof_complex16_scalar
private::mpi_sizeof_complex16_r1
private::mpi_sizeof_complex16_r2
private::mpi_sizeof_complex16_r3
private::mpi_sizeof_complex16_r4
private::mpi_sizeof_complex16_r5
private::mpi_sizeof_complex16_r6
private::mpi_sizeof_complex16_r7
private::mpi_sizeof_complex16_r8
private::mpi_sizeof_complex16_r9
private::mpi_sizeof_complex16_r10
private::mpi_sizeof_complex16_r11
private::mpi_sizeof_complex16_r12
private::mpi_sizeof_complex16_r13
private::mpi_sizeof_complex16_r14
private::mpi_sizeof_complex16_r15
private::mpi_sizeof_complex32_scalar
private::mpi_sizeof_complex32_r1
private::mpi_sizeof_complex32_r2
private::mpi_sizeof_complex32_r3
private::mpi_sizeof_complex32_r4
private::mpi_sizeof_complex32_r5
private::mpi_sizeof_complex32_r6
private::mpi_sizeof_complex32_r7
private::mpi_sizeof_complex32_r8
private::mpi_sizeof_complex32_r9
private::mpi_sizeof_complex32_r10
private::mpi_sizeof_complex32_r11
private::mpi_sizeof_complex32_r12
private::mpi_sizeof_complex32_r13
private::mpi_sizeof_complex32_r14
private::mpi_sizeof_complex32_r15
private::mpi_sizeof_complex64_scalar
private::mpi_sizeof_complex64_r1
private::mpi_sizeof_complex64_r2
private::mpi_sizeof_complex64_r3
private::mpi_sizeof_complex64_r4
private::mpi_sizeof_complex64_r5
private::mpi_sizeof_complex64_r6
private::mpi_sizeof_complex64_r7
private::mpi_sizeof_complex64_r8
private::mpi_sizeof_complex64_r9
private::mpi_sizeof_complex64_r10
private::mpi_sizeof_complex64_r11
private::mpi_sizeof_complex64_r12
private::mpi_sizeof_complex64_r13
private::mpi_sizeof_complex64_r14
private::mpi_sizeof_complex64_r15
private::mpi_sizeof_int16_scalar
private::mpi_sizeof_int16_r1
private::mpi_sizeof_int16_r2
private::mpi_sizeof_int16_r3
private::mpi_sizeof_int16_r4
private::mpi_sizeof_int16_r5
private::mpi_sizeof_int16_r6
private::mpi_sizeof_int16_r7
private::mpi_sizeof_int16_r8
private::mpi_sizeof_int16_r9
private::mpi_sizeof_int16_r10
private::mpi_sizeof_int16_r11
private::mpi_sizeof_int16_r12
private::mpi_sizeof_int16_r13
private::mpi_sizeof_int16_r14
private::mpi_sizeof_int16_r15
private::mpi_sizeof_int32_scalar
private::mpi_sizeof_int32_r1
private::mpi_sizeof_int32_r2
private::mpi_sizeof_int32_r3
private::mpi_sizeof_int32_r4
private::mpi_sizeof_int32_r5
private::mpi_sizeof_int32_r6
private::mpi_sizeof_int32_r7
private::mpi_sizeof_int32_r8
private::mpi_sizeof_int32_r9
private::mpi_sizeof_int32_r10
private::mpi_sizeof_int32_r11
private::mpi_sizeof_int32_r12
private::mpi_sizeof_int32_r13
private::mpi_sizeof_int32_r14
private::mpi_sizeof_int32_r15
private::mpi_sizeof_int64_scalar
private::mpi_sizeof_int64_r1
private::mpi_sizeof_int64_r2
private::mpi_sizeof_int64_r3
private::mpi_sizeof_int64_r4
private::mpi_sizeof_int64_r5
private::mpi_sizeof_int64_r6
private::mpi_sizeof_int64_r7
private::mpi_sizeof_int64_r8
private::mpi_sizeof_int64_r9
private::mpi_sizeof_int64_r10
private::mpi_sizeof_int64_r11
private::mpi_sizeof_int64_r12
private::mpi_sizeof_int64_r13
private::mpi_sizeof_int64_r14
private::mpi_sizeof_int64_r15
private::mpi_sizeof_int8_scalar
private::mpi_sizeof_int8_r1
private::mpi_sizeof_int8_r2
private::mpi_sizeof_int8_r3
private::mpi_sizeof_int8_r4
private::mpi_sizeof_int8_r5
private::mpi_sizeof_int8_r6
private::mpi_sizeof_int8_r7
private::mpi_sizeof_int8_r8
private::mpi_sizeof_int8_r9
private::mpi_sizeof_int8_r10
private::mpi_sizeof_int8_r11
private::mpi_sizeof_int8_r12
private::mpi_sizeof_int8_r13
private::mpi_sizeof_int8_r14
private::mpi_sizeof_int8_r15
private::mpi_sizeof_logical_scalar
private::mpi_sizeof_logical_r1
private::mpi_sizeof_logical_r2
private::mpi_sizeof_logical_r3
private::mpi_sizeof_logical_r4
private::mpi_sizeof_logical_r5
private::mpi_sizeof_logical_r6
private::mpi_sizeof_logical_r7
private::mpi_sizeof_logical_r8
private::mpi_sizeof_logical_r9
private::mpi_sizeof_logical_r10
private::mpi_sizeof_logical_r11
private::mpi_sizeof_logical_r12
private::mpi_sizeof_logical_r13
private::mpi_sizeof_logical_r14
private::mpi_sizeof_logical_r15
private::mpi_sizeof_real128_scalar
private::mpi_sizeof_real128_r1
private::mpi_sizeof_real128_r2
private::mpi_sizeof_real128_r3
private::mpi_sizeof_real128_r4
private::mpi_sizeof_real128_r5
private::mpi_sizeof_real128_r6
private::mpi_sizeof_real128_r7
private::mpi_sizeof_real128_r8
private::mpi_sizeof_real128_r9
private::mpi_sizeof_real128_r10
private::mpi_sizeof_real128_r11
private::mpi_sizeof_real128_r12
private::mpi_sizeof_real128_r13
private::mpi_sizeof_real128_r14
private::mpi_sizeof_real128_r15
private::mpi_sizeof_real16_scalar
private::mpi_sizeof_real16_r1
private::mpi_sizeof_real16_r2
private::mpi_sizeof_real16_r3
private::mpi_sizeof_real16_r4
private::mpi_sizeof_real16_r5
private::mpi_sizeof_real16_r6
private::mpi_sizeof_real16_r7
private::mpi_sizeof_real16_r8
private::mpi_sizeof_real16_r9
private::mpi_sizeof_real16_r10
private::mpi_sizeof_real16_r11
private::mpi_sizeof_real16_r12
private::mpi_sizeof_real16_r13
private::mpi_sizeof_real16_r14
private::mpi_sizeof_real16_r15
private::mpi_sizeof_real32_scalar
private::mpi_sizeof_real32_r1
private::mpi_sizeof_real32_r2
private::mpi_sizeof_real32_r3
private::mpi_sizeof_real32_r4
private::mpi_sizeof_real32_r5
private::mpi_sizeof_real32_r6
private::mpi_sizeof_real32_r7
private::mpi_sizeof_real32_r8
private::mpi_sizeof_real32_r9
private::mpi_sizeof_real32_r10
private::mpi_sizeof_real32_r11
private::mpi_sizeof_real32_r12
private::mpi_sizeof_real32_r13
private::mpi_sizeof_real32_r14
private::mpi_sizeof_real32_r15
private::mpi_sizeof_real64_scalar
private::mpi_sizeof_real64_r1
private::mpi_sizeof_real64_r2
private::mpi_sizeof_real64_r3
private::mpi_sizeof_real64_r4
private::mpi_sizeof_real64_r5
private::mpi_sizeof_real64_r6
private::mpi_sizeof_real64_r7
private::mpi_sizeof_real64_r8
private::mpi_sizeof_real64_r9
private::mpi_sizeof_real64_r10
private::mpi_sizeof_real64_r11
private::mpi_sizeof_real64_r12
private::mpi_sizeof_real64_r13
private::mpi_sizeof_real64_r14
private::mpi_sizeof_real64_r15
private::pmpi_sizeof_character_scalar
private::pmpi_sizeof_character_r1
private::pmpi_sizeof_character_r2
private::pmpi_sizeof_character_r3
private::pmpi_sizeof_character_r4
private::pmpi_sizeof_character_r5
private::pmpi_sizeof_character_r6
private::pmpi_sizeof_character_r7
private::pmpi_sizeof_character_r8
private::pmpi_sizeof_character_r9
private::pmpi_sizeof_character_r10
private::pmpi_sizeof_character_r11
private::pmpi_sizeof_character_r12
private::pmpi_sizeof_character_r13
private::pmpi_sizeof_character_r14
private::pmpi_sizeof_character_r15
private::pmpi_sizeof_complex128_scalar
private::pmpi_sizeof_complex128_r1
private::pmpi_sizeof_complex128_r2
private::pmpi_sizeof_complex128_r3
private::pmpi_sizeof_complex128_r4
private::pmpi_sizeof_complex128_r5
private::pmpi_sizeof_complex128_r6
private::pmpi_sizeof_complex128_r7
private::pmpi_sizeof_complex128_r8
private::pmpi_sizeof_complex128_r9
private::pmpi_sizeof_complex128_r10
private::pmpi_sizeof_complex128_r11
private::pmpi_sizeof_complex128_r12
private::pmpi_sizeof_complex128_r13
private::pmpi_sizeof_complex128_r14
private::pmpi_sizeof_complex128_r15
private::pmpi_sizeof_complex16_scalar
private::pmpi_sizeof_complex16_r1
private::pmpi_sizeof_complex16_r2
private::pmpi_sizeof_complex16_r3
private::pmpi_sizeof_complex16_r4
private::pmpi_sizeof_complex16_r5
private::pmpi_sizeof_complex16_r6
private::pmpi_sizeof_complex16_r7
private::pmpi_sizeof_complex16_r8
private::pmpi_sizeof_complex16_r9
private::pmpi_sizeof_complex16_r10
private::pmpi_sizeof_complex16_r11
private::pmpi_sizeof_complex16_r12
private::pmpi_sizeof_complex16_r13
private::pmpi_sizeof_complex16_r14
private::pmpi_sizeof_complex16_r15
private::pmpi_sizeof_complex32_scalar
private::pmpi_sizeof_complex32_r1
private::pmpi_sizeof_complex32_r2
private::pmpi_sizeof_complex32_r3
private::pmpi_sizeof_complex32_r4
private::pmpi_sizeof_complex32_r5
private::pmpi_sizeof_complex32_r6
private::pmpi_sizeof_complex32_r7
private::pmpi_sizeof_complex32_r8
private::pmpi_sizeof_complex32_r9
private::pmpi_sizeof_complex32_r10
private::pmpi_sizeof_complex32_r11
private::pmpi_sizeof_complex32_r12
private::pmpi_sizeof_complex32_r13
private::pmpi_sizeof_complex32_r14
private::pmpi_sizeof_complex32_r15
private::pmpi_sizeof_complex64_scalar
private::pmpi_sizeof_complex64_r1
private::pmpi_sizeof_complex64_r2
private::pmpi_sizeof_complex64_r3
private::pmpi_sizeof_complex64_r4
private::pmpi_sizeof_complex64_r5
private::pmpi_sizeof_complex64_r6
private::pmpi_sizeof_complex64_r7
private::pmpi_sizeof_complex64_r8
private::pmpi_sizeof_complex64_r9
private::pmpi_sizeof_complex64_r10
private::pmpi_sizeof_complex64_r11
private::pmpi_sizeof_complex64_r12
private::pmpi_sizeof_complex64_r13
private::pmpi_sizeof_complex64_r14
private::pmpi_sizeof_complex64_r15
private::pmpi_sizeof_int16_scalar
private::pmpi_sizeof_int16_r1
private::pmpi_sizeof_int16_r2
private::pmpi_sizeof_int16_r3
private::pmpi_sizeof_int16_r4
private::pmpi_sizeof_int16_r5
private::pmpi_sizeof_int16_r6
private::pmpi_sizeof_int16_r7
private::pmpi_sizeof_int16_r8
private::pmpi_sizeof_int16_r9
private::pmpi_sizeof_int16_r10
private::pmpi_sizeof_int16_r11
private::pmpi_sizeof_int16_r12
private::pmpi_sizeof_int16_r13
private::pmpi_sizeof_int16_r14
private::pmpi_sizeof_int16_r15
private::pmpi_sizeof_int32_scalar
private::pmpi_sizeof_int32_r1
private::pmpi_sizeof_int32_r2
private::pmpi_sizeof_int32_r3
private::pmpi_sizeof_int32_r4
private::pmpi_sizeof_int32_r5
private::pmpi_sizeof_int32_r6
private::pmpi_sizeof_int32_r7
private::pmpi_sizeof_int32_r8
private::pmpi_sizeof_int32_r9
private::pmpi_sizeof_int32_r10
private::pmpi_sizeof_int32_r11
private::pmpi_sizeof_int32_r12
private::pmpi_sizeof_int32_r13
private::pmpi_sizeof_int32_r14
private::pmpi_sizeof_int32_r15
private::pmpi_sizeof_int64_scalar
private::pmpi_sizeof_int64_r1
private::pmpi_sizeof_int64_r2
private::pmpi_sizeof_int64_r3
private::pmpi_sizeof_int64_r4
private::pmpi_sizeof_int64_r5
private::pmpi_sizeof_int64_r6
private::pmpi_sizeof_int64_r7
private::pmpi_sizeof_int64_r8
private::pmpi_sizeof_int64_r9
private::pmpi_sizeof_int64_r10
private::pmpi_sizeof_int64_r11
private::pmpi_sizeof_int64_r12
private::pmpi_sizeof_int64_r13
private::pmpi_sizeof_int64_r14
private::pmpi_sizeof_int64_r15
private::pmpi_sizeof_int8_scalar
private::pmpi_sizeof_int8_r1
private::pmpi_sizeof_int8_r2
private::pmpi_sizeof_int8_r3
private::pmpi_sizeof_int8_r4
private::pmpi_sizeof_int8_r5
private::pmpi_sizeof_int8_r6
private::pmpi_sizeof_int8_r7
private::pmpi_sizeof_int8_r8
private::pmpi_sizeof_int8_r9
private::pmpi_sizeof_int8_r10
private::pmpi_sizeof_int8_r11
private::pmpi_sizeof_int8_r12
private::pmpi_sizeof_int8_r13
private::pmpi_sizeof_int8_r14
private::pmpi_sizeof_int8_r15
private::pmpi_sizeof_logical_scalar
private::pmpi_sizeof_logical_r1
private::pmpi_sizeof_logical_r2
private::pmpi_sizeof_logical_r3
private::pmpi_sizeof_logical_r4
private::pmpi_sizeof_logical_r5
private::pmpi_sizeof_logical_r6
private::pmpi_sizeof_logical_r7
private::pmpi_sizeof_logical_r8
private::pmpi_sizeof_logical_r9
private::pmpi_sizeof_logical_r10
private::pmpi_sizeof_logical_r11
private::pmpi_sizeof_logical_r12
private::pmpi_sizeof_logical_r13
private::pmpi_sizeof_logical_r14
private::pmpi_sizeof_logical_r15
private::pmpi_sizeof_real128_scalar
private::pmpi_sizeof_real128_r1
private::pmpi_sizeof_real128_r2
private::pmpi_sizeof_real128_r3
private::pmpi_sizeof_real128_r4
private::pmpi_sizeof_real128_r5
private::pmpi_sizeof_real128_r6
private::pmpi_sizeof_real128_r7
private::pmpi_sizeof_real128_r8
private::pmpi_sizeof_real128_r9
private::pmpi_sizeof_real128_r10
private::pmpi_sizeof_real128_r11
private::pmpi_sizeof_real128_r12
private::pmpi_sizeof_real128_r13
private::pmpi_sizeof_real128_r14
private::pmpi_sizeof_real128_r15
private::pmpi_sizeof_real16_scalar
private::pmpi_sizeof_real16_r1
private::pmpi_sizeof_real16_r2
private::pmpi_sizeof_real16_r3
private::pmpi_sizeof_real16_r4
private::pmpi_sizeof_real16_r5
private::pmpi_sizeof_real16_r6
private::pmpi_sizeof_real16_r7
private::pmpi_sizeof_real16_r8
private::pmpi_sizeof_real16_r9
private::pmpi_sizeof_real16_r10
private::pmpi_sizeof_real16_r11
private::pmpi_sizeof_real16_r12
private::pmpi_sizeof_real16_r13
private::pmpi_sizeof_real16_r14
private::pmpi_sizeof_real16_r15
private::pmpi_sizeof_real32_scalar
private::pmpi_sizeof_real32_r1
private::pmpi_sizeof_real32_r2
private::pmpi_sizeof_real32_r3
private::pmpi_sizeof_real32_r4
private::pmpi_sizeof_real32_r5
private::pmpi_sizeof_real32_r6
private::pmpi_sizeof_real32_r7
private::pmpi_sizeof_real32_r8
private::pmpi_sizeof_real32_r9
private::pmpi_sizeof_real32_r10
private::pmpi_sizeof_real32_r11
private::pmpi_sizeof_real32_r12
private::pmpi_sizeof_real32_r13
private::pmpi_sizeof_real32_r14
private::pmpi_sizeof_real32_r15
private::pmpi_sizeof_real64_scalar
private::pmpi_sizeof_real64_r1
private::pmpi_sizeof_real64_r2
private::pmpi_sizeof_real64_r3
private::pmpi_sizeof_real64_r4
private::pmpi_sizeof_real64_r5
private::pmpi_sizeof_real64_r6
private::pmpi_sizeof_real64_r7
private::pmpi_sizeof_real64_r8
private::pmpi_sizeof_real64_r9
private::pmpi_sizeof_real64_r10
private::pmpi_sizeof_real64_r11
private::pmpi_sizeof_real64_r12
private::pmpi_sizeof_real64_r13
private::pmpi_sizeof_real64_r14
private::pmpi_sizeof_real64_r15
private::mpi_alloc_mem
private::mpi_comm_create_from_group
private::mpi_group_from_session_pset
private::mpi_intercomm_create_from_groups
private::mpi_session_get_info
private::mpi_session_get_nth_pset
private::mpi_session_get_nth_psetlen
private::mpi_session_get_pset_info
private::mpi_session_init
private::mpi_win_allocate
private::mpi_win_allocate_shared
private::mpi_win_shared_query
private::pmpi_alloc_mem
private::pmpi_comm_create_from_group
private::pmpi_group_from_session_pset
private::pmpi_intercomm_create_from_groups
private::pmpi_session_get_info
private::pmpi_session_get_nth_pset
private::pmpi_session_get_nth_psetlen
private::pmpi_session_get_pset_info
private::pmpi_session_init
private::pmpi_win_allocate
private::pmpi_win_allocate_shared
private::pmpi_win_shared_query
private::mpi_sizeof
private::pmpi_sizeof
private::mpi_bottom
private::mpi_in_place
private::mpi_argv_null
private::mpi_argvs_null
private::mpi_errcodes_ignore
private::mpi_status_ignore
private::mpi_statuses_ignore
private::mpi_unweighted
private::mpi_weights_empty
private::c_float
private::c_double
private::c_float_complex
private::c_double_complex
private::c_int32_t
private::c_int64_t
private::c_int
private::rk8
private::rk4
private::ck8
private::ck4
private::ik
private::lik
private::c_associated
private::c_funloc
private::c_funptr
private::c_f_pointer
private::c_loc
private::c_null_funptr
private::c_null_ptr
private::c_ptr
private::c_sizeof
private::c_int8_t
private::c_int16_t
private::c_int128_t
private::c_short
private::c_long
private::c_long_long
private::c_signed_char
private::c_size_t
private::c_intmax_t
private::c_intptr_t
private::c_ptrdiff_t
private::c_int_least8_t
private::c_int_fast8_t
private::c_int_least16_t
private::c_int_fast16_t
private::c_int_least32_t
private::c_int_fast32_t
private::c_int_least64_t
private::c_int_fast64_t
private::c_int_least128_t
private::c_int_fast128_t
private::c_long_double
private::c_long_double_complex
private::c_bool
private::c_char
private::c_null_char
private::c_alert
private::c_backspace
private::c_form_feed
private::c_new_line
private::c_carriage_return
private::c_horizontal_tab
private::c_vertical_tab
private::c_float128
private::c_float128_complex
private::c_uint8_t
private::c_uint16_t
private::c_uint32_t
private::c_uint64_t
private::c_uint128_t
private::c_unsigned_char
private::c_unsigned_short
private::c_unsigned
private::c_unsigned_long
private::c_unsigned_long_long
private::c_uintmax_t
private::c_uint_fast8_t
private::c_uint_fast16_t
private::c_uint_fast32_t
private::c_uint_fast64_t
private::c_uint_fast128_t
private::c_uint_least8_t
private::c_uint_least16_t
private::c_uint_least32_t
private::c_uint_least64_t
private::c_uint_least128_t
private::c_f_procpointer
private::posix_memalign
private::free
integer(4)::which_qr_decomposition
private::symm_matrix_allreduce_double
private::wy_gen_double
private::wy_left_double
private::wy_right_double
private::wy_symm_double
interface operator(.eq.)
end interface
private::operator(.eq.)
interface operator(.ne.)
end interface
private::operator(.ne.)
contains
subroutine bandred_real_double(obj,na,a_mat,a_dev,lda,nblk,nbw,matrixcols,numblocks,mpi_comm_rows,mpi_comm_cols,tmat,tmat_dev,wantdebug,usegpu,success,useqr,max_threads)
integer(4),intent(in)::obj
integer(4)::na
integer(4)::lda
real(8)::a_mat(1_8:int(lda,kind=8),1_8:*)
integer(8)::a_dev
integer(4)::nblk
integer(4)::nbw
integer(4)::matrixcols
integer(4)::numblocks
integer(4)::mpi_comm_rows
integer(4)::mpi_comm_cols
real(8)::tmat(1_8:int(nbw,kind=8),1_8:int(nbw,kind=8),1_8:*)
integer(8)::tmat_dev
logical(4),intent(in)::wantdebug
logical(4),intent(in)::usegpu
logical(4),intent(out)::success
logical(4),intent(in)::useqr
integer(4),intent(in)::max_threads
end
subroutine symm_matrix_allreduce_double(obj,n,a,lda,ldb,comm)
integer(4),intent(in)::obj
integer(4)::n
integer(4)::lda
real(8)::a(1_8:int(lda,kind=8),1_8:*)
integer(4)::ldb
integer(4)::comm
end
subroutine trans_ev_band_to_full_real_double(obj,na,nqc,nblk,nbw,a_mat,a_dev,lda,tmat,tmat_dev,q_mat,q_dev,ldq,matrixcols,numblocks,mpi_comm_rows,mpi_comm_cols,usegpu,useqr)
integer(4),intent(in)::obj
integer(4)::na
integer(4)::nqc
integer(4)::nblk
integer(4)::nbw
integer(4)::lda
real(8)::a_mat(1_8:int(lda,kind=8),1_8:*)
integer(8)::a_dev
real(8)::tmat(1_8:int(nbw,kind=8),1_8:int(nbw,kind=8),1_8:*)
integer(8)::tmat_dev
integer(4)::ldq
real(8)::q_mat(1_8:int(ldq,kind=8),1_8:*)
integer(8)::q_dev
integer(4)::matrixcols
integer(4)::numblocks
integer(4)::mpi_comm_rows
integer(4)::mpi_comm_cols
logical(4),intent(in)::usegpu
logical(4),intent(in)::useqr
end
subroutine tridiag_band_real_double(obj,na,nb,nblk,a_mat,a_dev,lda,d,e,matrixcols,hh_trans,mpi_comm_rows,mpi_comm_cols,communicator,usegpu,wantdebug,nrthreads)
integer(4),intent(in)::obj
integer(4),intent(in)::na
integer(4),intent(in)::nb
integer(4),intent(in)::nblk
integer(4),intent(in)::lda
real(8),intent(in)::a_mat(1_8:int(lda,kind=8),1_8:*)
integer(8)::a_dev
real(8),intent(out)::d(1_8:int(na,kind=8))
real(8),intent(out)::e(1_8:int(na,kind=8))
integer(4),intent(in)::matrixcols
real(8),allocatable,intent(out)::hh_trans(:,:)
integer(4),intent(in)::mpi_comm_rows
integer(4),intent(in)::mpi_comm_cols
integer(4),intent(in)::communicator
logical(4),intent(in)::usegpu
logical(4),intent(in)::wantdebug
integer(4),intent(in)::nrthreads
end
subroutine trans_ev_tridi_to_band_real_double(obj,na,nev,nblk,nbw,q,q_dev,ldq,matrixcols,hh_trans,mpi_comm_rows,mpi_comm_cols,wantdebug,usegpu,max_threads,success,kernel)
integer(4),intent(in)::obj
integer(4),intent(in)::na
integer(4),intent(in)::nev
integer(4),intent(in)::nblk
integer(4),intent(in)::nbw
integer(4),intent(in)::ldq
real(8)::q(1_8:int(ldq,kind=8),1_8:*)
integer(8)::q_dev
integer(4),intent(in)::matrixcols
real(8),intent(in)::hh_trans(:,:)
integer(4),intent(in)::mpi_comm_rows
integer(4),intent(in)::mpi_comm_cols
logical(4),intent(in)::wantdebug
logical(4),intent(in)::usegpu
integer(4),intent(in)::max_threads
logical(4)::success
integer(4),intent(in)::kernel
end
subroutine band_band_real_double(obj,na,nb,nbcol,nb2,nb2col,ab,ab2,d,e,communicator)
integer(4),intent(in)::obj
integer(4),intent(in)::na
integer(4),intent(in)::nb
integer(4),intent(in)::nbcol
integer(4),intent(in)::nb2
integer(4),intent(in)::nb2col
real(8),intent(inout)::ab(1_8:int(2_4*nb,kind=8),1_8:int(nbcol,kind=8))
real(8),intent(inout)::ab2(1_8:int(2_4*nb2,kind=8),1_8:int(nb2col,kind=8))
real(8),intent(out)::d(1_8:int(na,kind=8))
real(8),intent(out)::e(1_8:int(na,kind=8))
integer(4),intent(in)::communicator
end
subroutine wy_gen_double(obj,n,nb,w,y,tau,mem,lda)
integer(4),intent(in)::obj
integer(4),intent(in)::n
integer(4),intent(in)::nb
integer(4),intent(in)::lda
real(8),intent(out)::w(1_8:int(lda,kind=8),1_8:int(nb,kind=8))
real(8),intent(in)::y(1_8:int(lda,kind=8),1_8:int(nb,kind=8))
real(8),intent(in)::tau(1_8:int(nb,kind=8))
real(8),intent(in)::mem(1_8:int(nb,kind=8))
end
subroutine wy_left_double(obj,n,m,nb,a,lda,w,y,mem,lda2)
integer(4),intent(in)::obj
integer(4),intent(in)::n
integer(4),intent(in)::m
integer(4),intent(in)::nb
integer(4),intent(in)::lda
real(8),intent(inout)::a(1_8:int(lda,kind=8),1_8:*)
real(8),intent(in)::w(1_8:int(m,kind=8),1_8:int(nb,kind=8))
real(8),intent(in)::y(1_8:int(m,kind=8),1_8:int(nb,kind=8))
real(8),intent(inout)::mem(1_8:int(n,kind=8),1_8:int(nb,kind=8))
integer(4),intent(in)::lda2
end
subroutine wy_right_double(obj,n,m,nb,a,lda,w,y,mem,lda2)
integer(4),intent(in)::obj
integer(4),intent(in)::n
integer(4),intent(in)::m
integer(4),intent(in)::nb
integer(4),intent(in)::lda
real(8),intent(inout)::a(1_8:int(lda,kind=8),1_8:*)
real(8),intent(in)::w(1_8:int(m,kind=8),1_8:int(nb,kind=8))
real(8),intent(in)::y(1_8:int(m,kind=8),1_8:int(nb,kind=8))
real(8),intent(inout)::mem(1_8:int(n,kind=8),1_8:int(nb,kind=8))
integer(4),intent(in)::lda2
end
subroutine wy_symm_double(obj,n,nb,a,lda,w,y,mem,mem2,lda2)
integer(4),intent(in)::obj
integer(4),intent(in)::n
integer(4),intent(in)::nb
integer(4),intent(in)::lda
real(8),intent(inout)::a(1_8:int(lda,kind=8),1_8:*)
real(8),intent(in)::w(1_8:int(n,kind=8),1_8:int(nb,kind=8))
real(8),intent(in)::y(1_8:int(n,kind=8),1_8:int(nb,kind=8))
real(8)::mem(1_8:int(n,kind=8),1_8:int(nb,kind=8))
real(8)::mem2(1_8:int(nb,kind=8),1_8:int(nb,kind=8))
integer(4),intent(in)::lda2
end
end
