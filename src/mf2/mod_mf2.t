module mod_mf2
  use mod_mf2_phys
  use mod_functions_Bfield, only: mag
  use mod_amrvac

  implicit none
  public

contains

  subroutine mf2_activate()
    call mf2_phys_init()
  end subroutine mf2_activate

end module mod_mf2
