module mod_mf
  use mod_mf_phys
  use mod_functions_Bfield, only: mag
  use mod_amrvac

  implicit none
  public

contains

  subroutine mf_activate()
    call mf_phys_init()
  end subroutine mf_activate

end module mod_mf
