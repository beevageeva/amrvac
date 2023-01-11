There are two ways to add variables to the dat files:
# Extra variables
This method is used in many tests: ard/analytic_test_1d, demo/Advect_ParticleSampling_2D, hd/Gresho_Chan_2D, ...; 
in the tests folder run: 
  find . -name 'mod_usr.t' -exec grep -H "var_set_extravar" {} \;
to see all the tests which use this method.
It consists in:
1. assign an integer in the variable list w (in mod_usr.t, usr_init subroutine)
2. implement one of the user methods which are called every timestep and properly assign the pointer to it  in usr_init subroutine
for the following user defined subroutines: usr_process_grid, usr_modify_output,...
and set the extra variables.
This method adds extra variables in the dat file (which is also used for restart).

# New dat files
With this method an extra dat file is generated with new variables. A new module mod_convert was created. 
1. set convert_type to dat_generic_mpi
  &filelist
        ...
        convert_type = "dat_generic_mpi"
        ...
  /

2. add a convert method in usr_init subroutine (`use mod_convert`):

  call add_convert_method2(dump_vars, 4, "jx jy jz sxr", "_aux_") 

or

  call add_convert_method(dump_vars, 4, (/" jx", " jy", " jz", "sxr"/), "_aux_")

The first way is preferred as because Fortran requires the strrings in an array to have the same length and extra spaces might be necessary for this.
The last argument `_aux_` is the suffix added to `base_filename` for the name of the new dat file.

3. Implement `dump_vars` function: 

  function dump_vars(ixI^L, ixO^L, w, x, nwc) result(wnew)
    use mod_global_parameters
    use mod_thermal_emission
    integer, intent(in)             :: ixI^L,ixO^L, nwc
    double precision, intent(in)    :: w(ixO^S, 1:nw)
    double precision, intent(in)    :: x(ixO^S,1:ndim)
    double precision    :: wnew(ixO^S, 1:nwc)

    double precision :: current(ixI^S,7-2*ndir:3)
    integer :: idirmin,idir
    double precision    :: tmp(ixI^S)

    call get_current(w,ixI^L,ixO^L,idirmin,current)

    wnew(ixO^S,1) =  current(ixO^S,1)
    wnew(ixO^S,2) =  current(ixO^S,2)
    wnew(ixO^S,3) =  current(ixO^S,3)


    call get_SXR(ixI^L,ixO^L,w,x,te_fl_c,tmp,9,12)
    wnew(ixO^S,4) =  tmp(ixO^S)


  end function dump_vars

In the code this method is currently used: 
1. For the mhd model for dumping full variables by setting in the parameter file:
  &mhd_list
    mhd_dump_full_vars=.true.
  /  
A new file is created with hardcoded suffix `new`.

2. For the two-fluid  model for
  1. dumping full variables by setting in the parameter file:
    &twofl_list
      twofl_dump_full_vars=.true.
    /  
  A new file is created with hardcoded suffix `new`.

  2. dumping the collisional terms by setting in the parameter file:
    &twofl_list
      twofl_dump_coll_terms=.true.
    /  
  A new file is created with hardcoded suffix `_coll`.

 
