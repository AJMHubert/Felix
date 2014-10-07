!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!
! felixsim
!
! Richard Beanland, Keith Evans and Rudolf A Roemer
!
! (C) 2013/14, all right reserved
!
! Version: :VERSION:
! Date:    :DATE:
! Time:    :TIME:
! Status:  :RLSTATUS:
! Build:   :BUILD:
! Author:  :AUTHOR:
! 
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!
!  This file is part of felixsim.
!
!  felixsim is free software: you can redistribute it and/or modify
!  it under the terms of the GNU General Public License as published by
!  the Free Software Foundation, either version 3 of the License, or
!  (at your option) any later version.
!  
!  felixsim is distributed in the hope that it will be useful,
!  but WITHOUT ANY WARRANTY; without even the implied warranty of
!  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!  GNU General Public License for more details.
!  
!  You should have received a copy of the GNU General Public License
!  along with felixsim.  If not, see <http://www.gnu.org/licenses/>.
!
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
! $Id: gmodules.f90,v 1.11 2014/03/25 15:37:30 phsht Exp $
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

MODULE MyNumbers     
  IMPLICIT NONE

  INTEGER, PARAMETER :: IKIND = KIND(1)
  INTEGER, PARAMETER :: RKIND = KIND(1.0D0)
  INTEGER, PARAMETER :: CKIND = RKIND 

  REAL(KIND=RKIND) :: PI, TWOPI, ONEPLS, ONEMNS, &
       SQRTHALF, SQRTTWO

  REAL(KIND=RKIND), PARAMETER :: ZERO = 0.0, ONE = 1.0 ,TWO = 2.0, &
       THREE = 3.0, FOUR = 4.0
  COMPLEX(KIND=RKIND), PARAMETER :: CZERO = (0.0d0,0.0d0), CONE = (1.0d0,0.0d0), &
       CIMAGONE= (0.0d0,1.0d0)            

  REAL(KIND=RKIND), PARAMETER :: HALF = 0.5D0, QUARTER = 0.25D0, EIGHTH = 0.125D0, &
       THIRD=0.3333333333333333D0, TWOTHIRD=0.6666666666666D0, &
       NEGTHIRD=-0.3333333333333333D0, NEGTWOTHIRD=-0.6666666666666D0

  REAL(KIND=RKIND) :: TINY= 1.0D-9

  REAL(RKIND) :: RKiloByte,RMegaByte,RGigaByte,RTeraByte 
  
CONTAINS
  SUBROUTINE INIT_NUMBERS
    PI       = 4.0D0* ATAN(1.0D0)
    TWOPI    = 8.0D0* ATAN(1.0D0)
    ONEMNS   = SQRT(EPSILON(ONEMNS))
    ONEPLS   = ONE + ONEMNS
    ONEMNS   = ONE - ONEMNS
    SQRTHALF = DSQRT(0.5D0)
    SQRTTWO  = DSQRT(2.0D0)
    RKiloByte = 2.0D0**10.0D0
    RMegaByte = 2.0D0**20.0D0
    RGigaByte = 2.0D0**30.0D0
    RTeraByte = 2.0D0**40.0D0
    
  END SUBROUTINE INIT_NUMBERS

  FUNCTION ARG(X,Y)
    
    REAL(KIND=RKIND) ARG, X, Y
    
    IF( X > 0. ) THEN 
       ARG= ATAN(Y/X)
    ELSE IF ( (X == 0.) .and. (Y > 0. )) THEN 
       ARG = PI/2.0D0
    ELSE IF ( (X == 0.) .and. (Y < 0. )) THEN 
       ARG = -PI/2.0D0
    ELSE IF ( (X < 0. ) .and. (Y >= 0.)) THEN 
       ARG = PI + ATAN(Y/X)
    ELSE IF ( (X < 0. ) .and. (Y < 0. )) THEN 
       ARG = -PI + ATAN(Y/X)
    ELSE IF ( (X == 0.0) .and. (Y == 0.)) THEN
       PRINT*, "ARG(): both X and Y ==0, undefined --- using ARG=0"
       ARG=0.0D0
    ENDIF
    
    RETURN
  END FUNCTION ARG

  FUNCTION CROSS(a, b)
    REAL(RKIND), DIMENSION(3) :: CROSS
    REAL(RKIND), DIMENSION(3), INTENT(IN) :: a, b
    
    CROSS(1) = a(2) * b(3) - a(3) * b(2)
    CROSS(2) = a(3) * b(1) - a(1) * b(3)
    CROSS(3) = a(1) * b(2) - a(2) * b(1)
  END FUNCTION CROSS

  FUNCTION DOT(a, b)
    REAL(RKIND) :: DOT
    REAL(RKIND), DIMENSION(3), INTENT(IN) :: a, b
 
    DOT= a(1)*b(1)+a(2)*b(2)+a(3)*b(3)
  END FUNCTION DOT
  
END MODULE MyNumbers

MODULE MyMPI

  USE MPI
  USE MyNumbers

  INTEGER(IKIND) :: my_rank, p, srce, dest
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status_info
  
END MODULE MyMPI

MODULE MyFFTW   

  USE, INTRINSIC :: ISO_C_BINDING
  IMPLICIT NONE
  integer, parameter :: C_FFTW_R2R_KIND = C_INT32_T 
  INCLUDE  'fftw3.f03'
  
END MODULE MyFFTW
  


