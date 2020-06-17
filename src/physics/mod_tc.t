!> Thermal conduction for HD and MHD
!>
!> 10.07.2011 developed by Chun Xia and Rony Keppens
!> 01.09.2012 moved to modules folder by Oliver Porth
!> 13.10.2013 optimized further by Chun Xia
!> 12.03.2014 implemented RKL2 super timestepping scheme to reduce iterations 
!> and improve stability and accuracy up to second order in time by Chun Xia.
!> 23.08.2014 implemented saturation and perpendicular TC by Chun Xia
!> 12.01.2017 modulized by Chun Xia
!> 
!> PURPOSE: 
!> IN MHD ADD THE HEAT CONDUCTION SOURCE TO THE ENERGY EQUATION
!> S=DIV(KAPPA_i,j . GRAD_j T)
!> where KAPPA_i,j = tc_k_para b_i b_j + tc_k_perp (I - b_i b_j)
!> b_i b_j = B_i B_j / B**2, I is the unit matrix, and i, j= 1, 2, 3 for 3D
!> IN HD ADD THE HEAT CONDUCTION SOURCE TO THE ENERGY EQUATION
!> S=DIV(tc_k_para . GRAD T)
!> USAGE:
!> 1. in mod_usr.t -> subroutine usr_init(), add 
!>        unit_length=<your length unit>
!>        unit_numberdensity=<your number density unit>
!>        unit_velocity=<your velocity unit>
!>        unit_temperature=<your temperature unit>
!>    before call (m)hd_activate()
!> 2. to switch on thermal conduction in the (m)hd_list of amrvac.par add:
!>    (m)hd_thermal_conduction=.true.
!> 3. in the tc_list of amrvac.par :
!>    tc_perpendicular=.true.  ! (default .false.) turn on thermal conduction perpendicular to magnetic field 
!>    tc_saturate=.false.  ! (default .true. ) turn off thermal conduction saturate effect
!>    tc_dtpar=0.9/0.45/0.3 ! stable time step coefficient for 1D/2D/3D, decrease it for more stable run
!>    tc_slope_limiter='MC' ! choose limiter for slope-limited anisotropic thermal conduction in MHD

module mod_tc
  use mod_global_parameters, only: std_len
  use mod_geometry
  implicit none
  private
abstract interface
  subroutine get_temperature_subr_interface(w, x, ixI^L, ixO^L, res)
    use mod_global_parameters
    integer, intent(in)          :: ixI^L, ixO^L
    double precision, intent(in) :: w(ixI^S, 1:nw)
    double precision, intent(in) :: x(ixI^S, 1:ndim)
    double precision, intent(out):: res(ixI^S)

  end subroutine get_temperature_subr_interface
end interface

  public :: tc_init_mhd, tc_init_hd  

contains


  !ixArray rho, e,mag1,eaux
  !> Initialize the module
  !!as this is a separate module, as a difference from ambipolar,
  !the indices in w arrays are not known here
  !moreover, the indices might be different
  subroutine tc_init_mhd(phys_gamma, ixArray,get_temperature_subr)
    use mod_global_parameters
    use mod_supertimestepping, only: add_sts_method,sts_init
    double precision, intent(in) :: phys_gamma
    integer, intent(in) :: ixArray(:)
interface
  subroutine get_temperature_subr(w, x, ixI^L, ixO^L, res)
    use mod_global_parameters
    integer, intent(in)          :: ixI^L, ixO^L
    double precision, intent(in) :: w(ixI^S, 1:nw)
    double precision, intent(in) :: x(ixI^S, 1:ndim)
    double precision, intent(out):: res(ixI^S)

  end subroutine get_temperature_subr
end interface
  procedure (get_temperature_subr_interface), pointer :: get_temperature => null()


  !> Coefficient of thermal conductivity (parallel to magnetic field)
  double precision :: tc_k_para

  !> Coefficient of thermal conductivity perpendicular to magnetic field
  double precision :: tc_k_perp

  !> The adiabatic index
  double precision :: tc_gamma

  !> Name of slope limiter for transverse component of thermal flux 
  character(len=std_len)  :: tc_slope_limiter


  !> Logical switch for test constant conductivity
  logical :: tc_constant
  !> Calculate thermal conduction perpendicular to magnetic field (.true.) or not (.false.)
  logical :: tc_perpendicular=.false.

  !> Consider thermal conduction saturation effect (.true.) or not (.false.)
  logical :: tc_saturate=.true.
  !> Name of slope limiter for transverse component of thermal flux 
  integer :: rho_=-1,mag(1:3)=-1,e_=-1,eaux_=-1

    rho_ = ixArray(1)
    e_ = ixArray(2)
    mag(1) = ixArray(3)
    mag(2) = mag(1) + 1
    mag(3) = mag(2) + 1
    if(size(ixArray).eq.4) eaux_ = ixArray(4)

    tc_gamma=phys_gamma

    tc_slope_limiter='MC'

    tc_k_para=0.d0

    tc_k_perp=0.d0

    call tc_params_read_mhd(par_files)
  
    get_temperature => get_temperature_subr



    if(tc_k_para==0.d0 .and. tc_k_perp==0.d0) then
      if(SI_unit) then
        ! Spitzer thermal conductivity with SI units
        tc_k_para=8.d-12*unit_temperature**3.5d0/unit_length/unit_density/unit_velocity**3 
        ! thermal conductivity perpendicular to magnetic field
        tc_k_perp=4.d-30*unit_numberdensity**2/unit_magneticfield**2/unit_temperature**3*tc_k_para
      else
        ! Spitzer thermal conductivity with cgs units
        tc_k_para=8.d-7*unit_temperature**3.5d0/unit_length/unit_density/unit_velocity**3 
        ! thermal conductivity perpendicular to magnetic field
        tc_k_perp=4.d-10*unit_numberdensity**2/unit_magneticfield**2/unit_temperature**3*tc_k_para
      end if
    else
      tc_constant=.true.
    end if
      call sts_init()
      if(eaux_.ne.-1) then
        call add_sts_method(get_tc_dt_mhd,sts_set_source_tc_mhd,e_,e_,(/e_,eaux_/), (/1,1/),(/.true.,.true. /))
      else
        call add_sts_method(get_tc_dt_mhd,sts_set_source_tc_mhd,e_,e_,(/e_/), (/1/),(/.true./))
      endif


    contains

  !> Read this module"s parameters from a file
  subroutine tc_params_read_mhd(files)
    use mod_global_parameters, only: unitpar
    character(len=*), intent(in) :: files(:)
    integer                      :: n

    namelist /tc_list/ tc_perpendicular, tc_saturate, tc_slope_limiter, tc_k_para, tc_k_perp

    do n = 1, size(files)
       open(unitpar, file=trim(files(n)), status="old")
       read(unitpar, tc_list, end=111)
111    close(unitpar)
    end do

  end subroutine tc_params_read_mhd


  function get_tc_dt_mhd(w,ixI^L,ixO^L,dx^D,x)  result(dtnew)
    !Check diffusion time limit dt < tc_dtpar*dx_i**2/((gamma-1)*tc_k_para_i/rho)
    !where                      tc_k_para_i=tc_k_para*B_i**2/B**2
    !and                        T=p/rho
    use mod_global_parameters
    
    integer, intent(in) :: ixI^L, ixO^L
    double precision, intent(in) :: dx^D, x(ixI^S,1:ndim)
    double precision, intent(in) :: w(ixI^S,1:nw)
    double precision :: dtnew
    
    double precision :: dxinv(1:ndim),mf(ixI^S,1:ndir)
    double precision :: tmp2(ixI^S),tmp(ixI^S),Te(ixI^S),B2(ixI^S)
    double precision :: dtdiff_tcond
    integer          :: idim,ix^D


    ^D&dxinv(^D)=one/dx^D;
    
    call get_temperature(w,x,ixI^L,ixO^L,Te)

    !tc_k_para_i
    if(tc_constant) then
      tmp(ixO^S)=tc_k_para
    else
      tmp(ixO^S)=tc_k_para*dsqrt(Te(ixO^S)**5)/w(ixO^S,rho_)
    end if
    
    ! B
    if(B0field) then
      mf(ixO^S,:)=w(ixO^S,iw_mag(:))+block%B0(ixO^S,:,0)
    else
      mf(ixO^S,:)=w(ixO^S,iw_mag(:))
    end if
    ! B^-2
    B2(ixO^S)=sum(mf(ixO^S,:)**2,dim=ndim+1)
    ! B_i**2/B**2
    where(B2(ixO^S)/=0.d0)
      ^D&mf(ixO^S,^D)=mf(ixO^S,^D)**2/B2(ixO^S);
    elsewhere
      ^D&mf(ixO^S,^D)=1.d0;
    end where

    if(tc_saturate) B2(ixO^S)=22.d0*dsqrt(Te(ixO^S))

    do idim=1,ndim
      tmp2(ixO^S)=tmp(ixO^S)*mf(ixO^S,idim)
      if(tc_saturate) then
        where(tmp2(ixO^S)>B2(ixO^S))
          tmp2(ixO^S)=B2(ixO^S)
        end where
      end if
      ! dt< tc_dtpar * dx_idim**2/((gamma-1)*tc_k_para_i/rho*B_i**2/B**2)
      dtdiff_tcond=1d0/(tc_gamma-1.d0)/maxval(tmp2(ixO^S)*dxinv(idim)**2)
      ! limit the time step
      dtnew=min(dtnew,dtdiff_tcond)
    end do
    dtnew=dtnew/dble(ndim)
  
  end  function get_tc_dt_mhd


  !> anisotropic thermal conduction with slope limited symmetric scheme
  !> Sharma 2007 Journal of Computational Physics 227, 123

  subroutine sts_set_source_tc_mhd(ixI^L,ixO^L,w,x,wres,fix_conserve_at_step,my_dt,igrid,indexChangeStart, indexChangeN, indexChangeFixC)
      use mod_global_parameters
      use mod_geometry, only: divvector
      use mod_fix_conserve, only: store_flux_var

    integer, intent(in) :: ixI^L, ixO^L,igrid
    double precision, intent(in) ::  x(ixI^S,1:ndim), w(ixI^S,1:nw)
    double precision, intent(inout) ::  wres(ixI^S,1:nw)
    double precision, intent(in) :: my_dt
    logical, intent(in) :: fix_conserve_at_step
    integer, intent(in), dimension(:) :: indexChangeStart, indexChangeN
    logical, intent(in), dimension(:) :: indexChangeFixC


    !! qd store the heat conduction energy changing rate
    double precision :: qd(ixI^S)
    double precision, allocatable, dimension(:^D&,:) :: qvec   
 
    double precision, dimension(ixI^S,1:ndir) :: mf,Bc,Bcf
    double precision, dimension(ixI^S,1:ndim) :: gradT
    double precision, dimension(ixI^S) :: Te,ka,kaf,ke,kef,qdd,qe,Binv,minq,maxq,Bnorm
    double precision :: alpha,dxinv(ndim)
    integer, dimension(ndim) :: lowindex
    integer :: idims,idir,ix^D,ix^L,ixC^L,ixA^L,ixB^L

    allocate(qvec(ixI^S,1:ndim))
    ! coefficient of limiting on normal component
    if(ndim<3) then
      alpha=0.75d0
    else
      alpha=0.85d0
    end if
    ix^L=ixO^L^LADD1;

    dxinv=1.d0/dxlevel

    call get_temperature(w, x, ixI^L, ixI^L, Te)  !calculate Te in whole domain (+ghosts)
    ! T gradient at cell faces
    gradT=0.d0
    do idims=1,ndim
      ixBmin^D=ixmin^D;
      ixBmax^D=ixmax^D-kr(idims,^D);
      call gradientC(Te,ixI^L,ixB^L,idims,minq)
      gradT(ixB^S,idims)=minq(ixB^S)
    end do


    ! B vector
    if(B0field) then
      mf(ixI^S,:)=w(ixI^S,iw_mag(:))+block%B0(ixI^S,:,0)
    else
      mf(ixI^S,:)=w(ixI^S,iw_mag(:));
    end if
    ! |B|
    Binv(ix^S)=dsqrt(sum(mf(ix^S,:)**2,dim=ndim+1))
    where(Binv(ix^S)/=0.d0)
      Binv(ix^S)=1.d0/Binv(ix^S)
    elsewhere
      Binv(ix^S)=bigdouble
    end where
    ! b unit vector: magnetic field direction vector
    do idims=1,ndim
      mf(ix^S,idims)=mf(ix^S,idims)*Binv(ix^S)
    end do
    ! ixC is cell-corner index
    ixCmax^D=ixOmax^D; ixCmin^D=ixOmin^D-1;
    ! b unit vector at cell corner
    call cornerValue(ixI^L, ixC^L, mf, Bc)


    !!!get ka and ke
    if(tc_constant) then
      if(tc_perpendicular) then
        ka(ixC^S)=tc_k_para-tc_k_perp
        ke(ixC^S)=tc_k_perp
      else
        ka(ixC^S)=tc_k_para
      end if
    else
      if(trac) then
        where(Te(ix^S) < block%special_values(1))
          Te(ix^S)=block%special_values(1)
        end where
      end if
      minq(ix^S)=tc_k_para*sqrt(Te(ix^S)**5)
      ! conductivity at cell center
      call cornerValue(ixI^L, ixC^L, minq, ka)
      ! compensate with perpendicular conductivity
      if(tc_perpendicular) then
        minq(ix^S)=tc_k_perp*w(ix^S,rho_)**2*Binv(ix^S)**2/dsqrt(Te(ix^S))
        call cornerValue(ixI^L, ixC^L, minq, ke)
        where(ke(ixC^S)<ka(ixC^S))
          ka(ixC^S)=ka(ixC^S)-ke(ixC^S)
        elsewhere
          ka(ixC^S)=0.d0
          ke(ixC^S)=ka(ixC^S)
        end where
      end if
    end if
    !!!get ka and ke end


    if(tc_slope_limiter=='no') then


      ! calculate thermal conduction flux with symmetric scheme
      do idims=1,ndim
        call cornerValueVec(ixI^L, ixC^L, gradT, qd,idims,ndim)
        ! temperature gradient at cell corner
        qvec(ixC^S,idims)=qd(ixC^S)
      end do
      ! b grad T at cell corner
      qd(ixC^S)=sum(qvec(ixC^S,1:ndim)*Bc(ixC^S,1:ndim),dim=ndim+1)
      do idims=1,ndim
        ! TC flux at cell corner
        gradT(ixC^S,idims)=ka(ixC^S)*Bc(ixC^S,idims)*qd(ixC^S)
        if(tc_perpendicular) gradT(ixC^S,idims)=gradT(ixC^S,idims)+ke(ixC^S)*qvec(ixC^S,idims)
      end do
      ! TC flux at cell face
      qvec=0.d0
      do idims=1,ndim
        ixB^L=ixO^L-kr(idims,^D);
        ixAmax^D=ixOmax^D; ixAmin^D=ixBmin^D;
        call faceValue(ixI^L, ixA^L, gradT, qd,idims,ndim)
        qvec(ixA^S,idims)=qd(ixA^S)
        if(tc_saturate) then
          ! consider saturation (Cowie and Mckee 1977 ApJ, 211, 135)
          ! unsigned saturated TC flux = 5 phi rho c**3, c is isothermal sound speed
          ! averaged b at face centers
          call faceValue(ixI^L, ixA^L, Bc, Bcf(ixI^S,idims),idims,ndir)
          ixB^L=ixA^L+kr(idims,^D);
          qd(ixA^S)=2.75d0*(w(ixA^S,rho_)+w(ixB^S,rho_))*dsqrt(0.5d0*(Te(ixA^S)+Te(ixB^S)))**3*dabs(Bcf(ixA^S,idims))
         {do ix^DB=ixAmin^DB,ixAmax^DB\}
            if(dabs(qvec(ix^D,idims))>qd(ix^D)) then
              qvec(ix^D,idims)=sign(1.d0,qvec(ix^D,idims))*qd(ix^D)
            end if
         {end do\}
        end if
      end do

    else
      ! calculate thermal conduction flux with slope-limited symmetric scheme
      qvec=0.d0
      do idims=1,ndim
        ixB^L=ixO^L-kr(idims,^D);
        ixAmax^D=ixOmax^D; ixAmin^D=ixBmin^D;
        ! calculate normal of magnetic field
        ixB^L=ixA^L+kr(idims,^D);
        Bnorm(ixA^S)=0.5d0*(mf(ixA^S,idims)+mf(ixB^S,idims))


        !!calculate face values of Bc,ka,ke
        Bcf=0.d0
        kaf=0.d0
        kef=0.d0
        !!TODO as multiple operations are done here, not replaced yet by subroutine
        !as this is faster
        {do ix^DB=0,1 \}
           if({ ix^D==0 .and. ^D==idims | .or.}) then
             ixBmin^D=ixAmin^D-ix^D;
             ixBmax^D=ixAmax^D-ix^D;
             Bcf(ixA^S,1:ndim)=Bcf(ixA^S,1:ndim)+Bc(ixB^S,1:ndim)
             kaf(ixA^S)=kaf(ixA^S)+ka(ixB^S)
             if(tc_perpendicular) kef(ixA^S)=kef(ixA^S)+ke(ixB^S)
           end if
        {end do\}
        ! averaged b at face centers
        Bcf(ixA^S,1:ndim)=Bcf(ixA^S,1:ndim)*0.5d0**(ndim-1)
        ! averaged thermal conductivity at face centers
        kaf(ixA^S)=kaf(ixA^S)*0.5d0**(ndim-1)
        if(tc_perpendicular) kef(ixA^S)=kef(ixA^S)*0.5d0**(ndim-1)


        ! limited normal component
        minq(ixA^S)=min(alpha*gradT(ixA^S,idims),gradT(ixA^S,idims)/alpha)
        maxq(ixA^S)=max(alpha*gradT(ixA^S,idims),gradT(ixA^S,idims)/alpha)
        ! eq (19)
        call cornerValueVec(ixI^L, ixC^L, gradT, qdd,idims,ndim)
        ! eq (21)
        qe=0.d0
        {do ix^DB=0,1 \}
           qd(ixC^S)=qdd(ixC^S)
           if({ ix^D==0 .and. ^D==idims | .or.}) then
             ixBmin^D=ixAmin^D-ix^D;
             ixBmax^D=ixAmax^D-ix^D;
             where(qd(ixB^S)<=minq(ixA^S))
               qd(ixB^S)=minq(ixA^S)
             elsewhere(qd(ixB^S)>=maxq(ixA^S))
               qd(ixB^S)=maxq(ixA^S)
             end where
             qvec(ixA^S,idims)=qvec(ixA^S,idims)+Bc(ixB^S,idims)**2*qd(ixB^S)
             if(tc_perpendicular) qe(ixA^S)=qe(ixA^S)+qd(ixB^S) 
           end if
        {end do\}
        qvec(ixA^S,idims)=kaf(ixA^S)*qvec(ixA^S,idims)*0.5d0**(ndim-1)
        ! add normal flux from perpendicular conduction
        if(tc_perpendicular) qvec(ixA^S,idims)=qvec(ixA^S,idims)+kef(ixA^S)*qe(ixA^S)*0.5d0**(ndim-1)
        ! limited transverse component, eq (17)
        ixBmin^D=ixAmin^D;
        ixBmax^D=ixAmax^D+kr(idims,^D);
        do idir=1,ndim
          if(idir==idims) cycle
          qd(ixI^S)=slope_limiter(gradT(ixI^S,idir),ixI^L,ixB^L,idir,-1)
          qd(ixI^S)=slope_limiter(qd,ixI^L,ixA^L,idims,1)
          qvec(ixA^S,idims)=qvec(ixA^S,idims)+kaf(ixA^S)*Bnorm(ixA^S)*Bcf(ixA^S,idir)*qd(ixA^S)
        end do

        ! consider magnetic null point
        !where(Binv(ixA^S)==0.d0)
        !  qvec(ixA^S,idims)=tc_k_para*(0.5d0*(Te(ixA^S)+Te(ixB^S)))**2.5d0*gradT(ixA^S,idims)
        !end where

        if(tc_saturate) then
          ! consider saturation (Cowie and Mckee 1977 ApJ, 211, 135)
          ! unsigned saturated TC flux = 5 phi rho c**3, c is isothermal sound speed
          ixB^L=ixA^L+kr(idims,^D);
          qd(ixA^S)=2.75d0*(w(ixA^S,rho_)+w(ixB^S,rho_))*dsqrt(0.5d0*(Te(ixA^S)+Te(ixB^S)))**3*dabs(Bnorm(ixA^S))
         {do ix^DB=ixAmin^DB,ixAmax^DB\}
            if(dabs(qvec(ix^D,idims))>qd(ix^D)) then
        !      write(*,*) 'it',it,qvec(ix^D,idims),qd(ix^D),' TC saturated at ',&
        !      x(ix^D,:),' rho',w(ix^D,rho_),' Te',Te(ix^D)
              qvec(ix^D,idims)=sign(1.d0,qvec(ix^D,idims))*qd(ix^D)
            end if
         {end do\}
        end if
      end do
    end if
   if (fix_conserve_at_step)   call store_flux_var(qvec,e_,my_dt, igrid,indexChangeStart, indexChangeN, indexChangeFixC)

    qd=0.d0
    if(slab_uniform) then
      do idims=1,ndim
        qvec(ix^S,idims)=dxinv(idims)*qvec(ix^S,idims)
        ixB^L=ixO^L-kr(idims,^D);
        qd(ixO^S)=qd(ixO^S)+qvec(ixO^S,idims)-qvec(ixB^S,idims)
      end do
    else
      do idims=1,ndim
        qvec(ix^S,idims)=qvec(ix^S,idims)*block%surfaceC(ix^S,idims)
        ixB^L=ixO^L-kr(idims,^D);
        qd(ixO^S)=qd(ixO^S)+qvec(ixO^S,idims)-qvec(ixB^S,idims)
      end do
      qd(ixO^S)=qd(ixO^S)/block%dvolume(ixO^S)
    end if
    deallocate(qvec)
    wres(ixO^S,e_)=qd(ixO^S)
    if(eaux_ .ne. -1)wres(ixO^S,eaux_)=qd(ixO^S)
    
  end subroutine sts_set_source_tc_mhd

  function slope_limiter(f,ixI^L,ixO^L,idims,pm) result(lf)
    use mod_global_parameters
    integer, intent(in) :: ixI^L, ixO^L, idims, pm
    double precision, intent(in) :: f(ixI^S)
    double precision :: lf(ixI^S)

    double precision :: signf(ixI^S)
    integer :: ixB^L

    ixB^L=ixO^L+pm*kr(idims,^D);
    signf(ixO^S)=sign(1.d0,f(ixO^S))
    select case(tc_slope_limiter)
     case('minmod')
       ! minmod limiter
       lf(ixO^S)=signf(ixO^S)*max(0.d0,min(abs(f(ixO^S)),signf(ixO^S)*f(ixB^S)))
     case ('MC')
       ! montonized central limiter Woodward and Collela limiter (eq.3.51h), a factor of 2 is pulled out
       lf(ixO^S)=two*signf(ixO^S)* &
            max(zero,min(dabs(f(ixO^S)),signf(ixO^S)*f(ixB^S),&
            signf(ixO^S)*quarter*(f(ixB^S)+f(ixO^S))))
     case ('superbee')
       ! Roes superbee limiter (eq.3.51i)
       lf(ixO^S)=signf(ixO^S)* &
            max(zero,min(two*dabs(f(ixO^S)),signf(ixO^S)*f(ixB^S)),&
            min(dabs(f(ixO^S)),two*signf(ixO^S)*f(ixB^S)))
     case ('koren')
       ! Barry Koren Right variant
       lf(ixO^S)=signf(ixO^S)* &
            max(zero,min(two*dabs(f(ixO^S)),two*signf(ixO^S)*f(ixB^S),&
            (two*f(ixB^S)*signf(ixO^S)+dabs(f(ixO^S)))*third))
     case default
       call mpistop("Unknown slope limiter for thermal conduction")
    end select

  end function slope_limiter


  end subroutine tc_init_mhd



  !> Calculate gradient of a scalar q at cell interfaces in direction idir
  subroutine gradientC(q,ixI^L,ixO^L,idir,gradq)
    use mod_global_parameters

    integer, intent(in)             :: ixI^L, ixO^L, idir
    double precision, intent(in)    :: q(ixI^S)
    double precision, intent(inout) :: gradq(ixI^S)
    integer                         :: jxO^L

    associate(x=>block%x)

    jxO^L=ixO^L+kr(idir,^D);
    select case(coordinate)
    case(Cartesian)
      gradq(ixO^S)=(q(jxO^S)-q(ixO^S))/dxlevel(idir)
    case(Cartesian_stretched)
      gradq(ixO^S)=(q(jxO^S)-q(ixO^S))/(x(jxO^S,idir)-x(ixO^S,idir))
    case(spherical)
      select case(idir)
      case(1)
        gradq(ixO^S)=(q(jxO^S)-q(ixO^S))/(x(jxO^S,1)-x(ixO^S,1))
        {^NOONED
      case(2)
        gradq(ixO^S)=(q(jxO^S)-q(ixO^S))/( (x(jxO^S,2)-x(ixO^S,2))*x(ixO^S,1) )
        }
        {^IFTHREED
      case(3)
        gradq(ixO^S)=(q(jxO^S)-q(ixO^S))/( (x(jxO^S,3)-x(ixO^S,3))*x(ixO^S,1)*dsin(x(ixO^S,2)) )
        }
      end select
    case(cylindrical)
      if(idir==phi_) then
        gradq(ixO^S)=(q(jxO^S)-q(ixO^S))/((x(jxO^S,phi_)-x(ixO^S,phi_))*x(ixO^S,r_))
      else
        gradq(ixO^S)=(q(jxO^S)-q(ixO^S))/(x(jxO^S,idir)-x(ixO^S,idir))
      end if
    case default
      call mpistop('Unknown geometry')
    end select

    end associate
  end subroutine gradientC

  subroutine tc_init_hd(phys_gamma, ixArray,get_temperature_subr)
    use mod_global_parameters
    use mod_supertimestepping, only: add_sts_method,sts_init

    double precision, intent(in) :: phys_gamma
    integer, intent(in) :: ixArray(:)
interface
  subroutine get_temperature_subr(w, x, ixI^L, ixO^L, res)
    use mod_global_parameters
    integer, intent(in)          :: ixI^L, ixO^L
    double precision, intent(in) :: w(ixI^S, 1:nw)
    double precision, intent(in) :: x(ixI^S, 1:ndim)
    double precision, intent(out):: res(ixI^S)

  end subroutine get_temperature_subr
end interface
  procedure (get_temperature_subr_interface), pointer :: get_temperature => null()

  !> Coefficient of thermal conductivity (parallel to magnetic field)
  double precision :: tc_k_para

  !> The adiabatic index
  double precision :: tc_gamma



  !> Consider thermal conduction saturation effect (.true.) or not (.false.)
  logical :: tc_saturate=.true.
  integer :: rho_=-1,e_=-1

    rho_ = ixArray(1)
    e_ = ixArray(2)

    tc_gamma=phys_gamma

    tc_k_para=0.d0


    call tc_params_read_hd(par_files)
  
    get_temperature => get_temperature_subr

    if(tc_k_para==0.d0 ) then
      if(SI_unit) then
        ! Spitzer thermal conductivity with SI units
        tc_k_para=8.d-12*unit_temperature**3.5d0/unit_length/unit_density/unit_velocity**3 
      else
        ! Spitzer thermal conductivity with cgs units
        tc_k_para=8.d-7*unit_temperature**3.5d0/unit_length/unit_density/unit_velocity**3 
      end if
    end if

    call add_sts_method(get_tc_dt_hd,sts_set_source_tc_hd,e_,e_,(/e_/), (/1/),(/.true./))
  contains


  !> Read this module"s parameters from a file
  subroutine tc_params_read_hd(files)
    use mod_global_parameters, only: unitpar
    character(len=*), intent(in) :: files(:)
    integer                      :: n

    namelist /tc_list/ tc_saturate, tc_k_para

    do n = 1, size(files)
       open(unitpar, file=trim(files(n)), status="old")
       read(unitpar, tc_list, end=111)
111    close(unitpar)
    end do

  end subroutine tc_params_read_hd

  function get_tc_dt_hd(w,ixI^L,ixO^L,dx^D,x)  result(dtnew)
    ! Check diffusion time limit dt < tc_dtpar * dx_i**2 / ((gamma-1)*tc_k_para_i/rho)
    use mod_global_parameters

    integer, intent(in) :: ixI^L, ixO^L
    double precision, intent(in) :: dx^D, x(ixI^S,1:ndim)
    double precision, intent(in) :: w(ixI^S,1:nw)
    double precision :: dtnew

    double precision :: dxinv(1:ndim), tmp(ixI^S), Te(ixI^S)
    double precision :: dtdiff_tcond,dtdiff_tsat
    integer          :: idim,ix^D

    ^D&dxinv(^D)=one/dx^D;

    call get_temperature(w, x, ixI^L, ixO^L, Te)  
    tmp(ixO^S)=(tc_gamma-one)*tc_k_para*dsqrt((Te(ixO^S))**5)/w(ixO^S,rho_)

    do idim=1,ndim
       ! dt< tc_dtpar * dx_idim**2/((gamma-1)*tc_k_para_idim/rho)
       dtdiff_tcond=1d0/maxval(tmp(ixO^S)*dxinv(idim)**2)
       if(tc_saturate) then
         ! dt< tc_dtpar* dx_idim**2/((gamma-1)*sqrt(Te)*5*phi)
         dtdiff_tsat=1d0/maxval((tc_gamma-1.d0)*dsqrt(Te(ixO^S))*&
                     5.d0*dxinv(idim)**2)
         ! choose the slower flux (bigger time scale) between classic and saturated
         dtdiff_tcond=max(dtdiff_tcond,dtdiff_tsat)
       end if
       ! limit the time step
       dtnew=min(dtnew,dtdiff_tcond)
    end do
    dtnew=dtnew/dble(ndim)

  end function get_tc_dt_hd




  subroutine sts_set_source_tc_hd(ixI^L,ixO^L,w,x,wres,fix_conserve_at_step,my_dt,igrid,indexChangeStart, indexChangeN, indexChangeFixC )
      use mod_global_parameters
      use mod_geometry, only: divvector
      use mod_fix_conserve, only: store_flux_var

      integer, intent(in) :: ixI^L, ixO^L,igrid
      double precision, intent(in) ::  x(ixI^S,1:ndim), w(ixI^S,1:nw)
      double precision, intent(inout) ::  wres(ixI^S,1:nw)
      double precision, intent(in) :: my_dt
      logical, intent(in) :: fix_conserve_at_step
      integer, intent(in), dimension(:) :: indexChangeStart, indexChangeN
      logical, intent(in), dimension(:) :: indexChangeFixC

    double precision :: gradT(ixI^S,1:ndim),Te(ixI^S),ke(ixI^S)
    double precision :: qd(ixI^S)
    double precision, allocatable, dimension(:^D&,:) :: qvec   

    double precision :: dxinv(ndim)
    integer, dimension(ndim)       :: lowindex
    integer :: idims,ix^D,ix^L,ixC^L,ixA^L,ixB^L,ixD^L

    allocate(qvec(ixI^S,1:ndim))
    ix^L=ixO^L^LADD1;
    ! ixC is cell-corner index
    ixCmax^D=ixOmax^D; ixCmin^D=ixOmin^D-1;

    dxinv=1.d0/dxlevel

    call get_temperature(w, x, ixI^L, ixI^L, Te)  !calculate Te in whole domain (+ghosts)

    ixAmax^D=ixmax^D; ixAmin^D=ixmin^D-1;
    ! cell corner temperature
    call cornerValue(ixI^L, ixA^L, Te, ke)

    ! T gradient (central difference) at cell corners
    gradT=0.d0
    do idims=1,ndim
      ixBmin^D=ixmin^D;
      ixBmax^D=ixmax^D-kr(idims,^D);
      call gradient(ke,ixI^L,ixB^L,idims,qd)
      gradT(ixB^S,idims)=qd(ixB^S)
    end do
    ! transition region adaptive conduction
    if(trac) then
      where(Te(ix^S) < block%special_values(1))
        ke(ix^S)=block%special_values(1)
      end where
    end if
    ! cell corner conduction flux
    do idims=1,ndim
      gradT(ixC^S,idims)=gradT(ixC^S,idims)*tc_k_para*sqrt(ke(ixC^S)**5)
    end do

    if(tc_saturate) then
      ! consider saturation with unsigned saturated TC flux = 5 phi rho c**3
      ! saturation flux at cell center
      qd(ix^S)=5.d0*w(ix^S,rho_)*dsqrt(Te(ix^S)**3)
      call cornerValue(ixI^L, ixC^L, qd, ke)

      ! magnitude of cell corner conduction flux
      qd(ixC^S)=norm2(gradT(ixC^S,:),dim=ndim+1)
      {do ix^DB=ixCmin^DB,ixCmax^DB\}
        if(qd(ix^D)>ke(ix^D)) then
          ke(ix^D)=ke(ix^D)/qd(ix^D)
          do idims=1,ndim
            gradT(ix^D,idims)=ke(ix^D)*gradT(ix^D,idims)
          end do
        end if
      {end do\}
    end if

    ! conductionflux at cell face
    qvec=0.d0
    do idims=1,ndim
      ixB^L=ixO^L-kr(idims,^D);
      ixAmax^D=ixOmax^D; ixAmin^D=ixBmin^D;
      call faceValue(ixI^L, ixA^L, gradT, qd,idims,ndim)
      qvec(ixA^S,idims)=qd(ixA^S)
    end do

   if (fix_conserve_at_step)   call store_flux_var(qvec,e_,my_dt, igrid,indexChangeStart, indexChangeN, indexChangeFixC)
    qd=0.d0
    if(slab_uniform) then
      do idims=1,ndim
        qvec(ix^S,idims)=dxinv(idims)*qvec(ix^S,idims)
        ixB^L=ixO^L-kr(idims,^D);
        qd(ixO^S)=qd(ixO^S)+qvec(ixO^S,idims)-qvec(ixB^S,idims)
      end do
    else
      do idims=1,ndim
        qvec(ix^S,idims)=qvec(ix^S,idims)*block%surfaceC(ix^S,idims)
        ixB^L=ixO^L-kr(idims,^D);
        qd(ixO^S)=qd(ixO^S)+qvec(ixO^S,idims)-qvec(ixB^S,idims)
      end do
      qd(ixO^S)=qd(ixO^S)/block%dvolume(ixO^S)
    end if
    deallocate(qvec)

    wres(ixO^S,e_)=qd(ixO^S)

  end subroutine sts_set_source_tc_hd

  end subroutine tc_init_hd


!!-------------------------------------------------------
  subroutine cornerValue(ixI^L, ixC^L, qd, ke)
    use mod_global_parameters
    double precision, intent(in) :: qd(ixI^S)
    integer, intent(in) :: ixI^L, ixC^L
    double precision, intent(out) :: ke(ixI^S)
    
    integer :: ix^D, ixB^L

      ke=0.d0
      {do ix^DB=0,1\}
        ixBmin^D=ixCmin^D+ix^D;
        ixBmax^D=ixCmax^D+ix^D;
        ke(ixC^S)=ke(ixC^S)+qd(ixB^S)
      {end do\}
      ke(ixC^S)=0.5d0**ndim*ke(ixC^S)

  end subroutine cornerValue


  subroutine cornerValueVec(ixI^L, ixC^L, qd, ke,idims,ndim1)
    use mod_global_parameters
    double precision, intent(in) :: qd(ixI^S,1:ndim1)
    integer, intent(in) :: ixI^L, ixC^L, idims,ndim1
    double precision, intent(out) :: ke(ixI^S)
    integer :: ix^D,ixB^L
        ke=0.d0
        {do ix^DB=0,1 \}
           if({ ix^D==0 .and. ^D==idims | .or.}) then
             ixBmin^D=ixCmin^D+ix^D;
             ixBmax^D=ixCmax^D+ix^D;
             ke(ixC^S)=ke(ixC^S)+qd(ixB^S,idims)
           end if
        {end do\}
        ! temperature gradient at cell corner
        ke(ixC^S)=ke(ixC^S)*0.5d0**(ndim-1)

  end subroutine cornerValueVec

  subroutine faceValue(ixI^L, ixC^L, qd, ke,idims,ndim1)
    use mod_global_parameters
    double precision, intent(in) :: qd(ixI^S,1:ndim1)
    integer, intent(in) :: ixI^L, ixC^L, idims,ndim1
    double precision, intent(out) :: ke(ixI^S)
    integer :: ix^D,ixB^L

        ke=0.d0
        {do ix^DB=0,1 \}
           if({ ix^D==0 .and. ^D==idims | .or.}) then
             ixBmin^D=ixCmin^D - ix^D;
             ixBmax^D=ixCmax^D - ix^D;
             ke(ixC^S)=ke(ixC^S)+qd(ixB^S,idims)
           end if
        {end do\}
        ! temperature gradient at cell corner
        ke(ixC^S)=ke(ixC^S)*0.5d0**(ndim-1)

  end subroutine faceValue

end module mod_tc
