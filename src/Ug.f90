!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!
! felixsim
!
! Richard Beanland, Keith Evans, Rudolf A Roemer and Alexander Hubert
!
! (C) 2013/14, all rights reserved
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

SUBROUTINE StructureFactorInitialisation (IErr)

  USE MyNumbers
  USE WriteToScreen

  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara; USE SPara
  USE BlochPara; USE MyFFTW

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: ind,jnd,knd,lnd,mnd,oddindlorentz,evenindlorentz,oddindgauss, &
       evenindgauss,currentatom,IErr,Iuid,Iplan_forward,IPseudo,IHalfPsize
  INTEGER(IKIND),DIMENSION(2) :: IPos,ILoc
  COMPLEX(CKIND) :: CVgij,CFpseudo
  REAL(RKIND) :: RMeanInnerPotentialVolts,RScatteringFactor,Lorentzian,Gaussian,Kirkland,&
        RScattFacToVolts,RPMag,Rx,Ry,Rr,RPalpha,RTheta,Rfold,RRscale
  CHARACTER*200 :: SPrintString
  
  !Conversion factor from scattering factors to volts. h^2/(2pi*m0*e*omega), see e.g. Kirkland eqn. 6.9 and C.5
  !NB RVolume is already in A unlike RPlanckConstant
  RScattFacToVolts=(RPlanckConstant**2)*(RAngstromConversion**2)/(TWOPI*RElectronMass*RElectronCharge*RVolume)
  !Count Pseudoatoms
  IPseudo=0
  DO jnd=1,INAtomsUnitCell
    IF (IAtomicNumber(jnd).GE.105) IPseudo=IPseudo+1
  END DO
  !Calculate pseudoatom potentials
  IPsize=2048!Size of the array used to calculate the pseudoatom FFT, global variable, must be an EVEN number (preferably 2^n)!For later: give CPseudoAtom ,CPseudoScatt a 3rd dimension?
  IHalfPsize=IPsize/2
  ALLOCATE(CPseudoAtom(IPsize,IPsize,IPseudo),STAT=IErr)!Matrices with Pseudoatom potentials (real space)- could just have one reusable matrix to save memory
  ALLOCATE(CPseudoScatt(IPsize,IPsize,IPseudo),STAT=IErr)!Matrices with Pseudoatom scattering factor (reciprocal space)
  ALLOCATE(RFourPiGsquaredVc(IPsize,IPsize),STAT=IErr)!4*pi*G^2^Volume of unit cell, to convert electron density to potential
  RRScale=0.016!Real space size of 1 pixel working in Angstroms; max radius is 512*RRScale=4.096A
  RPScale=TWO*TWOPI/(RRscale*IPsize)!Reciprocal  size of 1 pixel is 2pi/(RRscale*(IPsize/2)): roughly pi/2 for RRScale = 0.04
  !make 4piG^2Vc, centred on corner to match the FFT
  DO ind=1,IPsize/2
    DO jnd=1,IPsize/2
      Rx=RPScale*(REAL(ind)-HALF)
      Ry=RPScale*(REAL(jnd)-HALF)
      !Rr=1/(FOUR*PI*(Rx*Rx+Ry*Ry))
      Rr=1/((Rx*Rx+Ry*Ry))!not sure of the 4pi
      RFourPiGsquaredVc(ind,jnd)=Rr
      RFourPiGsquaredVc(IPsize+1-ind,jnd)=Rr
      RFourPiGsquaredVc(ind,IPsize+1-jnd)=Rr
      RFourPiGsquaredVc(IPsize+1-ind,IPsize+1-jnd)=Rr
    END DO
  END DO
  IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) PRINT*,"Pseudoatom matrix A^-1 per pixel",RPScale
  !Magnitude of pseudoatom potential, in volts
  mnd=0!pseudoatom counter
  DO lnd=1,INAtomsUnitCell 
    IF (IAtomicNumber(lnd).GE.105) THEN!we have a pseudoatom
      mnd=mnd+1
      RPalpha=10.0*RIsoDW(lnd)!The Debye-Waller factor is used to determine alpha for pseudoatoms
      IF (IAtomicNumber(lnd).EQ.105) Rfold=ZERO   !Ja
      IF (IAtomicNumber(lnd).EQ.106) Rfold=ONE    !Jb
      IF (IAtomicNumber(lnd).EQ.107) Rfold=TWO    !Jc
      IF (IAtomicNumber(lnd).EQ.108) Rfold=THREE  !Jd
      IF (IAtomicNumber(lnd).EQ.109) Rfold=FOUR   !Je
      IF (IAtomicNumber(lnd).EQ.110) Rfold=SIX    !Jf
      !electron density in real space
      DO ind=1,IPsize
        DO jnd=1,IPsize
          Rx=RRScale*(REAL(ind-(IPsize/2))-HALF)!x&y run from e.g. -511.5 to +511.5 picometres
          Ry=RRScale*(REAL(jnd-(IPsize/2))-HALF)
          Rr=SQRT(Rx*Rx+Ry*Ry)
          Rtheta=ACOS(Rx/Rr)
          CPseudoAtom(ind,jnd,mnd)=CMPLX(RPalpha*Rr*EXP(-RPalpha*Rr)*COS(Rfold*Rtheta),ZERO)!Easier to make a complex input to fftw rather than fanny around with the different format needed for a real input. Lazy.
        END DO
      END DO
      IF (my_rank.EQ.0) THEN!output to check
        WRITE(SPrintString,FMT='(A15,I1,A4)') "PseudoPotential",mnd,".img"
        OPEN(UNIT=IChOutWIImage, ERR=10, STATUS= 'UNKNOWN', FILE=SPrintString,&
             FORM='UNFORMATTED',ACCESS='DIRECT',IOSTAT=IErr,RECL=IPsize*IByteSize)
        DO jnd = 1,IPsize
            !WRITE(IChOutWIImage,rec=jnd) RFourPiGsquaredVc(jnd,:)
            WRITE(IChOutWIImage,rec=jnd) REAL(CPseudoAtom(jnd,:,mnd))
        END DO
        CLOSE(IChOutWIImage,IOSTAT=IErr)
      END IF
      !CPseudoScatt = a 2d fft of RPseudoAtom
      CALL dfftw_plan_dft_2d_ (Iplan_forward, IPsize,IPsize, CPseudoAtom(:,:,mnd), CPseudoScatt(:,:,mnd),&
           FFTW_FORWARD,FFTW_ESTIMATE )!Could be moved to an initialisation step if there are no other plans?
      CALL dfftw_execute_ (Iplan_forward)
      CALL dfftw_destroy_plan_ (Iplan_forward)
      CPseudoScatt(:,:,mnd)=CPseudoScatt(:,:,mnd)*RFourPiGsquaredVc!convert electron density to potential
      !Shift the fft origin to the middle using CPseudoAtom as a temp store
      CPseudoAtom(1:IHalfPsize,1:IHalfPsize,mnd)=CPseudoScatt(1+IHalfPsize:IPsize,1+IHalfPsize:IPsize,mnd)
      CPseudoAtom(1+IHalfPsize:IPsize,1+IHalfPsize:IPsize,mnd)=CPseudoScatt(1:IHalfPsize,1:IHalfPsize,mnd)
      CPseudoAtom(1+IHalfPsize:IPsize,1:IHalfPsize,mnd)=CPseudoScatt(1:IHalfPsize,1+IHalfPsize:IPsize,mnd)
      CPseudoAtom(1:IHalfPsize,1+IHalfPsize:IPsize,mnd)=CPseudoScatt(1+IHalfPsize:IPsize,1:IHalfPsize,mnd)
      CPseudoScatt(:,:,mnd)=CPseudoAtom(:,:,mnd)
      RPMag=0.529177/MAXVAL(ABS(CPseudoScatt(:,:,mnd)))!the maximum scattering factor value equals the Bohr radius, the same as a hydrogen atom
      CPseudoScatt(:,:,mnd)=CPseudoAtom(:,:,mnd)*RPMag
      IF (my_rank.EQ.0) THEN!output to check
        WRITE(SPrintString,FMT='(A12,I1,A4)') "PseudoFactor",mnd,".img"
        OPEN(UNIT=IChOutWIImage, ERR=10, STATUS= 'UNKNOWN', FILE=SPrintString,&
             FORM='UNFORMATTED',ACCESS='DIRECT',IOSTAT=IErr,RECL=IPsize*IByteSize)
        DO jnd = 1,IPsize
            WRITE(IChOutWIImage,rec=jnd) ABS(CPseudoScatt(jnd,:,mnd))
        END DO
        CLOSE(IChOutWIImage,IOSTAT=IErr)
      END IF
    END IF
  END DO

  !Calculate lower diagonal of Ug matrix
  CUgMatNoAbs = CZERO
  DO ind=2,nReflections
    DO jnd=1,ind-1
      RCurrentGMagnitude = RgMatrixMagnitude(ind,jnd)!g-vector magnitude, global variable
      !The Fourier component of the potential Vg goes in location (i,j)
      CVgij=CZERO!this is in Volts
      mnd=0!pseudoatom counter
      DO lnd=1,INAtomsUnitCell
        ICurrentZ = IAtomicNumber(lnd)!Atomic number, NB passed as a global variable for absorption
        IF (ICurrentZ.LT.105) THEN!It's not a pseudoatom
          CALL AtomicScatteringFactor(RScatteringFactor,IErr)!returns RScatteringFactor as a global variable
          ! Occupancy
          RScatteringFactor = RScatteringFactor*ROccupancy(lnd)
          !Debye-Waller factor
          IF (IAnisoDebyeWallerFactorFlag.EQ.0) THEN
            IF(RIsoDW(lnd).GT.10.OR.RIsoDW(lnd).LT.0) RIsoDW(lnd) = RDebyeWallerConstant
            !Isotropic D-W factor exp(-B sin(theta)^2/lamda^2) = exp(-Bs^2)=exp(-Bg^2/16pi^2), see e.g. Bird&King
            RScatteringFactor = RScatteringFactor*EXP(-RIsoDW(lnd)*(RCurrentGMagnitude**2)/(FOUR*TWOPI**2) )
          ELSE!this will need sorting out, not sure if it works
            RScatteringFactor = RScatteringFactor * &
              EXP(-DOT_PRODUCT(RgMatrix(ind,jnd,:), &
              MATMUL( RAnisotropicDebyeWallerFactorTensor( &
              RAnisoDW(lnd),:,:),RgMatrix(ind,jnd,:))))
          END IF
          !The structure factor equation, complex Vg(ind,jnd)=RScattFacToVolts * sum(f*exp(-ig.r) in Volts
          CVgij=CVgij+RScatteringFactor*RScattFacToVolts*EXP(-CIMAGONE*DOT_PRODUCT(RgMatrix(ind,jnd,:), RAtomCoordinate(lnd,:)) )
        ELSE!pseudoatom
          mnd=mnd+1
          CALL PseudoFac(CFpseudo,ind,jnd,mnd,IErr)
          !IF (my_rank.EQ.0) PRINT*,ind,jnd,"CFpseudo",CFpseudo
          ! Occupancy
          CFpseudo = CFpseudo*ROccupancy(lnd)
          !Debye-Waller factor - isotropic only, for now
          IF (IAnisoDebyeWallerFactorFlag.NE.0) THEN
            IF (my_rank.EQ.0) PRINT*,"Pseudo atom - isotropic Debye-Waller factor only!"
            IErr=1
            RETURN
          END IF
          !DW factor: Need to work out how to get it the from the real atom at the same site!
          CFpseudo = CFpseudo*EXP(-RIsoDW(lnd+1)*(RCurrentGMagnitude**2)/(FOUR*TWOPI**2) )!assume it is the next atom in the list, for now
          CVgij=CVgij+CFpseudo*EXP(-CIMAGONE*DOT_PRODUCT(RgMatrix(ind,jnd,:), RAtomCoordinate(lnd,:)) )
        END IF
      ENDDO
      CUgMatNoAbs(ind,jnd)=CVgij!This is still the Vg(i,j) matrix, not yet Ug(i,j)
    ENDDO
  ENDDO
  !Ug=Vg*(2me/hbar^2).  To give it in Angstrom units divide by 10^20.*TWOPI*TWOPI
  CUgMatNoAbs=CUgMatNoAbs*TWO*RElectronMass*RRelativisticCorrection*RElectronCharge/((RPlanckConstant**2)*(RAngstromConversion**2))
  !NB Only the lower half of the Vg matrix was calculated, this completes the upper half
  CUgMatNoAbs = CUgMatNoAbs + CONJG(TRANSPOSE(CUgMatNoAbs))
  DO ind=1,nReflections
    CUgMatNoAbs(ind,ind)=CZERO
  END DO
  IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) THEN
    PRINT*,"Ug matrix, without absorption (nm^-2)"!NB * by 100 to get it in nm^-2
	DO ind =1,16
     WRITE(SPrintString,FMT='(3(1X,I3),A1,8(1X,F7.3,F7.3))') NINT(Rhkl(ind,:)),":",100*CUgMatNoAbs(ind,1:8)
     PRINT*,TRIM(SPrintString)
    END DO
  END IF
  
  !Calculate the mean inner potential as the sum of scattering factors at g=0 multiplied by h^2/(2pi*m0*e*CellVolume)
  RMeanInnerPotential=ZERO
  RCurrentGMagnitude=ZERO
  DO ind=1,INAtomsUnitCell
    ICurrentZ = IAtomicNumber(ind)
    IF(ICurrentZ.LT.105) THEN!It's not a pseudoatom
      CALL AtomicScatteringFactor(RScatteringFactor,IErr)
      IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) PRINT*,ind,"g=0",RScatteringFactor
      RMeanInnerPotential = RMeanInnerPotential+RScatteringFactor
    END IF
  END DO
  RMeanInnerPotential = RMeanInnerPotential*RScattFacToVolts
  IF(my_rank.EQ.0) THEN
    WRITE(SPrintString,FMT='(A20,F5.2,1X,A6)') "MeanInnerPotential= ",RMeanInnerPotential," Volts"
    PRINT*,TRIM(ADJUSTL(SPrintString))
  END IF
  !fg^2 at at g ->infinity should be 2Z/a0, where a0 is the Bohr radius 0.5292A
  RCurrentGMagnitude=100000.0!TWOPI/(RElectronWaveLength*
  DO ind=1,INAtomsUnitCell
    ICurrentZ = IAtomicNumber(ind)
    mnd=0!pseudoatom counter
    IF(ICurrentZ.LT.105) THEN!It's not a pseudoatom
      CALL AtomicScatteringFactor(RScatteringFactor,IErr)
    ELSE
      mnd=mnd+1
      CALL PseudoFac(CFpseudo,1,1,mnd,IErr)
    END IF
    IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) PRINT*,ind,"Z check at g->infinity",RScatteringFactor*RCurrentGMagnitude*RCurrentGMagnitude*0.529177/2.0
  END DO

  ! high-energy approximation (not HOLZ compatible)
  !Wave vector in crystal
  !K^2=k^2+U0
  RBigK= SQRT(RElectronWaveVectorMagnitude**2 + RMeanInnerPotential)
  IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) THEN
    WRITE(SPrintString,FMT='(A4,F5.1,A10)') "K = ",RBigK," Angstroms"
      PRINT*,TRIM(ADJUSTL(SPrintString))
  END IF

  !--------------------------------------------------------------------
  !Count equivalent Ugs
  IF (IInitialSimulationFLAG.EQ.1) THEN
  !Equivalent Ug's are identified by the sum of their abs(indices)plus the sum of abs(Ug)'s with no absorption
    RgSumMat = SUM(ABS(RgMatrix),3)+RgMatrixMagnitude+ABS(REAL(CUgMatNoAbs))+ABS(AIMAG(CUgMatNoAbs))
    ISymmetryRelations = 0_IKIND 
    Iuid = 0_IKIND 
    DO ind = 1,nReflections
      DO jnd = 1,ind
        IF(ISymmetryRelations(ind,jnd).NE.0) THEN
          CYCLE
        ELSE
          Iuid = Iuid + 1_IKIND
          !Ug Fill the symmetry relation matrix with incrementing numbers that have the sign of the imaginary part
          WHERE (ABS(RgSumMat-ABS(RgSumMat(ind,jnd))).LE.RTolerance)
            ISymmetryRelations = Iuid*SIGN(1_IKIND,NINT(AIMAG(CUgMatNoAbs)/(TINY**2)))
          END WHERE
        END IF
      END DO
    END DO

    IF(my_rank.EQ.0) THEN
      WRITE(SPrintString,FMT='(I5,A25)') Iuid," unique structure factors"
      PRINT*,TRIM(ADJUSTL(SPrintString))
    END IF
    IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) THEN
      PRINT*,"hkl: symmetry matrix"
      DO ind =1,16
        WRITE(SPrintString,FMT='(3(1X,I3),A1,12(2X,I3))') NINT(Rhkl(ind,:)),":",ISymmetryRelations(ind,1:12)
        PRINT*,TRIM(SPrintString)
      END DO
    END IF

    !Link each key with its Ug, from 1 to the number of unique Ug's Iuid
    ALLOCATE(IEquivalentUgKey(Iuid),STAT=IErr)
    ALLOCATE(CUniqueUg(Iuid),STAT=IErr)
    IF( IErr.NE.0 ) THEN
      PRINT*,"SetupUgsToRefine(",my_rank,")error allocating IEquivalentUgKey or CUniqueUg"
      RETURN
    END IF
    DO ind = 1,Iuid
      ILoc = MINLOC(ABS(ISymmetryRelations-ind))
      IEquivalentUgKey(ind) = ind
      CUniqueUg(ind) = CUgMatNoAbs(ILoc(1),ILoc(2))
    END DO
    !Put them in descending order of magnitude  
    CALL ReSortUgs(IEquivalentUgKey,CUniqueUg,Iuid)  
  END IF
  RETURN
  
10 IErr=1
  IF(my_rank.EQ.0)PRINT*,"Error in saving pseudoatom image"

END SUBROUTINE StructureFactorInitialisation

!!$%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SUBROUTINE UpdateUgMatrix(IErr)

  USE MyNumbers
  USE WriteToScreen

  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara; USE SPara
  USE BlochPara; USE MyFFTW

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE
  
  INTEGER(IKIND) :: IUniqueUgs,ind,jnd,knd,lnd,mnd,evenindlorentz,oddindgauss,evenindgauss,IErr
  INTEGER(IKIND),DIMENSION(2) :: ILoc  
  REAL(RKIND) :: Lorentzian,Gaussian,Kirkland,RScattFacToVolts,RScatteringFactor
  REAL(RKIND),DIMENSION(3) :: RCurrentG
  COMPLEX(CKIND) :: CVgij,CFpseudo
  CHARACTER*200 :: SPrintString

  !CReset Ug matrix  
  CUgMatNoAbs = CZERO
  !RScattFacToVolts=(RPlanckConstant**2)*(RAngstromConversion**2)/(TWOPI*RElectronMass*RElectronCharge)
  !Work through unique Ug's
  IUniqueUgs=SIZE(IEquivalentUgKey)
  DO ind=1,IUniqueUgs
    !number of this Ug
    jnd=IEquivalentUgKey(ind)
    !find the position of this Ug in the matrix
    ILoc = MINLOC(ABS(ISymmetryRelations-jnd))
    RCurrentG = RgMatrix(ILoc(1),ILoc(2),:)!g-vector, local variable
    RCurrentGMagnitude = RgMatrixMagnitude(ILoc(1),ILoc(2))!g-vector magnitude, global variable
    CVgij=CZERO
    mnd=0!pseudoatom counter
    DO lnd=1,INAtomsUnitCell
      ICurrentZ = IAtomicNumber(lnd)!Atomic number, global variable
      RCurrentB = RIsoDW(lnd)!Debye-Waller constant, global variable
      IF (ICurrentZ.LT.105) THEN!It's not a pseudoatom 
        CALL AtomicScatteringFactor(RScatteringFactor,IErr)
        ! Occupancy
        RScatteringFactor = RScatteringFactor*ROccupancy(lnd)
        !Debye-Waller factor
        IF (IAnisoDebyeWallerFactorFlag.EQ.0) THEN
          IF(RCurrentB.GT.10.OR.RCurrentB.LT.0) RCurrentB = RDebyeWallerConstant
          !Isotropic D-W factor exp(-B sin(theta)^2/lamda^2) = exp(-Bs^2)=exp(-Bg^2/16pi^2), see e.g. Bird&King
          RScatteringFactor = RScatteringFactor*EXP(-RIsoDW(lnd)*(RCurrentGMagnitude**2)/(FOUR*TWOPI**2) )
        ELSE!this will need sorting out, not sure if it works
          RScatteringFactor = RScatteringFactor * &
            EXP(-DOT_PRODUCT(RgMatrix(ILoc(1),ILoc(2),:), &
            MATMUL( RAnisotropicDebyeWallerFactorTensor( &
            RAnisoDW(lnd),:,:),RgMatrix(ILoc(1),ILoc(2),:))))
        END IF
        !The structure factor equation, complex Vg(ILoc(1),ILoc(2))=sum(f*exp(-ig.r) in Volts
        CVgij = CVgij+RScatteringFactor*EXP(-CIMAGONE*DOT_PRODUCT(RCurrentG, RAtomCoordinate(lnd,:)) )
      ELSE!It is a pseudoatom
        mnd=mnd+1
        CALL PseudoFac(CFpseudo,ILoc(1),ILoc(2),mnd,IErr)
        ! Occupancy
        CFpseudo = CFpseudo*ROccupancy(lnd)
        !Debye-Waller factor - isotropic only, for now
        IF (IAnisoDebyeWallerFactorFlag.NE.0) THEN
          IF (my_rank.EQ.0) PRINT*,"Pseudo atom - isotropic Debye-Waller factor only!"
          IErr=1
          RETURN
        END IF
        !DW factor: Need to work out how to get it the from the real atom at the same site!
        CFpseudo=CFpseudo*EXP(-RIsoDW(lnd+1)*(RCurrentGMagnitude**2)/(FOUR*TWOPI**2) )!assume it is the next atom in the list, for now
        CVgij=CVgij+CFpseudo*EXP(-CIMAGONE*DOT_PRODUCT(RgMatrix(ILoc(1),ILoc(2),:), RAtomCoordinate(lnd,:)) )
      END IF
    END DO
    !now replace the values in the Ug matrix
    WHERE(ISymmetryRelations.EQ.jnd)
      CUgMatNoAbs=CVgij
    END WHERE
    !NB for imaginary potential U(g)=U(-g)*
    WHERE(ISymmetryRelations.EQ.-jnd)
      CUgMatNoAbs = CONJG(CVgij)
    END WHERE
  END DO

  CUgMatNoAbs=CUgMatNoAbs*RRelativisticCorrection/(PI*RVolume)
  DO ind=1,nReflections!zero diagonal
     CUgMatNoAbs(ind,ind)=ZERO
  ENDDO
  
  IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) THEN
    PRINT*,"Updated Ug matrix, without absorption (nm^-2)"
	DO ind =1,16
     WRITE(SPrintString,FMT='(3(1X,I3),A1,8(1X,F7.3,F7.3))') NINT(Rhkl(ind,:)),":",100*CUgMatNoAbs(ind,1:8)
     PRINT*,TRIM(SPrintString)
    END DO
  END IF
  
  END SUBROUTINE UpdateUgMatrix

!!$%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  SUBROUTINE AtomicScatteringFactor(RScatteringFactor,IErr)  

  USE MyNumbers
  USE WriteToScreen

  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara
  USE BlochPara

  USE IChannels
  
  IMPLICIT NONE

  INTEGER(IKIND) :: ind,jnd,knd,IErr
  REAL(RKIND) :: Kirkland,GAUSSIAN,LORENTZIAN,RScatteringFactor
  
  RScatteringFactor = ZERO
  SELECT CASE (IScatterFactorMethodFLAG)
          
  CASE(0) ! Kirkland Method using 3 Gaussians and 3 Lorentzians, NB Kirkland scattering factor is in Angstrom units
    !NB atomic number and g-vector passed as global variables
    RScatteringFactor = Kirkland(RCurrentGMagnitude)
      
  CASE(1) ! 8 Parameter Method with Scattering Parameters from Peng et al 1996 
    DO ind = 1,4
      !Peng Method uses summation of 4 Gaussians
      RScatteringFactor = RScatteringFactor + &
        GAUSSIAN(RScattFactors(ICurrentZ,ind),RCurrentGMagnitude,ZERO, & 
        SQRT(2/RScattFactors(ICurrentZ,ind+4)),ZERO)
    END DO
  
  CASE(2) ! 8 Parameter Method with Scattering Parameters from Doyle and Turner Method (1968)
    DO ind = 1,4
      jnd = ind*2
      knd = ind*2 -1
      !Doyle &Turner uses summation of 4 Gaussians
      RScatteringFactor = RScatteringFactor + &
        GAUSSIAN(RScattFactors(ICurrentZ,knd),RCurrentGMagnitude,ZERO, & 
        SQRT(2/RScattFactors(ICurrentZ,jnd)),ZERO)
    END DO
      
  CASE(3) ! 10 Parameter method with Scattering Parameters from Lobato et al. 2014
    DO ind = 1,5
      jnd=ind+5
      RScatteringFactor = RScatteringFactor + &
        LORENTZIAN(RScattFactors(ICurrentZ,ind)* &
       (TWO+RScattFactors(ICurrentZ,jnd)*(RCurrentGMagnitude**TWO)),ONE, &
        RScattFactors(ICurrentZ,jnd)*(RCurrentGMagnitude**TWO),ZERO)
    END DO

    END SELECT

  END SUBROUTINE AtomicScatteringFactor

!!$%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SUBROUTINE Absorption (IErr)  

  USE MyNumbers
  USE WriteToScreen

  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara
  USE BlochPara

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: ind,jnd,knd,lnd,mnd,IErr,IUniqueUgs,ILocalUgCountMin,ILocalUgCountMax
  INTEGER(IKIND),DIMENSION(2) :: ILoc
  REAL(RKIND) :: Rintegral,RfPrime,RScattFacToVolts,RAbsPreFactor
  REAL(RKIND),DIMENSION(3) :: RCurrentG
  COMPLEX(CKIND),DIMENSION(:),ALLOCATABLE :: CLocalUgPrime,CUgPrime
  REAL(RKIND),DIMENSION(:),ALLOCATABLE :: RLocalUgReal,RLocalUgImag,RUgReal,RUgImag
  INTEGER(IKIND),DIMENSION(:),ALLOCATABLE :: Ipos,Inum
  COMPLEX(CKIND) :: CVgPrime,CFpseudo
  CHARACTER*200 :: SPrintString
  
  RScattFacToVolts=(RPlanckConstant**2)*(RAngstromConversion**2)/(TWOPI*RElectronMass*RElectronCharge*RVolume)
  RAbsPreFactor=TWO*RPlanckConstant*RAngstromConversion/(RElectronMass*RElectronVelocity)
  
  CUgMatPrime = CZERO
  SELECT CASE (IAbsorbFLAG)
    CASE(1)
    !!$ Proportional
    CUgMatPrime = CUgMatNoAbs*EXP(CIMAGONE*PI/2)*(RAbsorptionPercentage/100_RKIND)
  
    CASE(2)
    !!$ Bird & King
    !Work through unique Ug's
    IUniqueUgs=SIZE(IEquivalentUgKey)
    !Allocations for the U'g to be calculated by this core  
    ILocalUgCountMin= (IUniqueUgs*(my_rank)/p)+1
    ILocalUgCountMax= (IUniqueUgs*(my_rank+1)/p)
    ALLOCATE(Ipos(p),Inum(p),STAT=IErr)
    ALLOCATE(CLocalUgPrime(ILocalUgCountMax-ILocalUgCountMin+1),STAT=IErr)!U'g list for this core
    ALLOCATE(RLocalUgReal(ILocalUgCountMax-ILocalUgCountMin+1),STAT=IErr)!U'g list for this core [Re,Im]
    ALLOCATE(RLocalUgImag(ILocalUgCountMax-ILocalUgCountMin+1),STAT=IErr)!U'g list for this core [Re,Im]
    ALLOCATE(CUgPrime(IUniqueUgs),STAT=IErr)!complete U'g list
    ALLOCATE(RUgReal(IUniqueUgs),STAT=IErr)!complete U'g list [Re]
    ALLOCATE(RUgImag(IUniqueUgs),STAT=IErr)!complete U'g list [Im]
    IF( IErr.NE.0 ) THEN
      PRINT*,"Absorption(",my_rank,") error in allocations"
      RETURN
    ENDIF
    DO ind = 1,p!p is the number of cores
      Ipos(ind) = IUniqueUgs*(ind-1)/p!position in the MPI buffer
      Inum(ind) = IUniqueUgs*(ind)/p - IUniqueUgs*(ind-1)/p!number of U'g components
    END DO
    DO ind=ILocalUgCountMin,ILocalUgCountMax!Different U'g s for each core
      CVgPrime = CZERO
      !number of this Ug
      jnd=IEquivalentUgKey(ind)
      !find the position of this Ug in the matrix
      ILoc = MINLOC(ABS(ISymmetryRelations-jnd))
      RCurrentG = RgMatrix(ILoc(1),ILoc(2),:)!g-vector, local variable
      RCurrentGMagnitude = RgMatrixMagnitude(ILoc(1),ILoc(2))!g-vector magnitude, global variable
      lnd=0!pseudoatom counter
      !Structure factor calculation for absorptive form factors
      DO knd=1,INAtomsUnitCell
        ICurrentZ = IAtomicNumber(knd)!Atomic number, global variable
        RCurrentB = RIsoDW(knd)!Debye-Waller constant, global variable
        IF (ICurrentZ.LT.105) THEN!It's not a pseudoatom 
          !Uses numerical integration to calculate absorptive form factor f'
          CALL DoubleIntegrate(RfPrime,IErr)!NB uses Kirkland scattering factors
          IF(IErr.NE.0) THEN
            PRINT*,"Absorption(",my_rank,") error in Bird&King integration"
            RETURN
          END IF
        ELSE!It is a pseudoatom, proportional model 
          lnd=lnd+1
          CALL PseudoFac(CFpseudo,ILoc(1),ILoc(2),lnd,IErr)
          RfPrime=CFpseudo*EXP(CIMAGONE*PI/2)*(RAbsorptionPercentage/HUNDRED)
          !RfPrime=ZERO
        END IF
        ! Occupancy
        RfPrime=RfPrime*ROccupancy(knd)
        !Debye Waller factor, isotropic only 
        RfPrime=RfPrime*EXP(-RIsoDW(knd)*(RCurrentGMagnitude**2)/(4*TWOPI**2) )
        !Absorptive Structure factor equation giving imaginary potential
        CVgPrime=CVgPrime+CIMAGONE*Rfprime*EXP(-CIMAGONE*DOT_PRODUCT(RCurrentG,RAtomCoordinate(knd,:)) )
      END DO
      !V'g in volts
      CVgPrime=CVgPrime*RAbsPreFactor*RScattFacToVolts
      !Convert to U'g=V'g*(2*m*e/h^2)	  
      CLocalUgPrime(ind-ILocalUgCountMin+1)=CVgPrime*TWO*RElectronMass*RRelativisticCorrection*RElectronCharge/((RPlanckConstant*RAngstromConversion)**2)
    END DO
    !I give up trying to MPI a complex number, do it with two real ones
    RLocalUgReal=REAL(CLocalUgPrime)
    RLocalUgImag=AIMAG(CLocalUgPrime)
    !MPI gatherv the new U'g s into CUgPrime--------------------------------------------------------------------  
    !NB MPI_GATHERV(BufferToSend,No.of elements,datatype,  ReceivingArray,No.of elements,)
    CALL MPI_GATHERV(RLocalUgReal,SIZE(RLocalUgReal),MPI_DOUBLE_PRECISION,&
                   RUgReal,Inum,Ipos,MPI_DOUBLE_PRECISION,&
                   root,MPI_COMM_WORLD,IErr)
    CALL MPI_GATHERV(RLocalUgImag,SIZE(RLocalUgImag),MPI_DOUBLE_PRECISION,&
                   RUgImag,Inum,Ipos,MPI_DOUBLE_PRECISION,&
                   root,MPI_COMM_WORLD,IErr)
    IF(IErr.NE.0) THEN
      PRINT*,"Felixfunction(",my_rank,")error",IErr,"in MPI_GATHERV"
      RETURN
    END IF
    !=====================================and send out the full list to all cores
    CALL MPI_BCAST(RUgReal,IUniqueUgs,MPI_DOUBLE_PRECISION,&
                   root,MPI_COMM_WORLD,IErr)
    CALL MPI_BCAST(RUgImag,IUniqueUgs,MPI_DOUBLE_PRECISION,&
                   root,MPI_COMM_WORLD,IErr)
    !=====================================
    DO ind=1,IUniqueUgs
      CUgPrime(ind)=CMPLX(RUgReal(ind),RUgImag(ind))
    END DO
    !Construct CUgMatPrime
    DO ind=1,IUniqueUgs
      !number of this Ug
      jnd=IEquivalentUgKey(ind)
      !Fill CUgMatPrime
      WHERE(ISymmetryRelations.EQ.jnd)
        CUgMatPrime = CUgPrime(ind)
      END WHERE
      !NB for imaginary potential U'(g)=-U'(-g)*
      WHERE(ISymmetryRelations.EQ.-jnd)
        CUgMatPrime = -CONJG(CUgPrime(ind))
      END WHERE
    END DO
	
    CASE Default
	!Default case is no absorption
	
  END SELECT
  !The final Ug matrix with absorption
  CUgMat=CUgMatNoAbs+CUgMatPrime
  
  IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) THEN
   PRINT*,"Ug matrix, including absorption (nm^-2)"
	DO ind =1,16
     WRITE(SPrintString,FMT='(3(1X,I3),A1,8(1X,F7.3,F7.3))') NINT(Rhkl(ind,:)),":",100*CUgMat(ind,1:8)
     PRINT*,TRIM(SPrintString)
    END DO
  END IF	   
	   
END SUBROUTINE Absorption

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

SUBROUTINE DoubleIntegrate(RResult,IErr) 

  USE MyNumbers
  USE WriteToScreen

  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara
  USE BlochPara

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND), PARAMETER :: inf=1
  INTEGER(IKIND), PARAMETER :: limit=500
  INTEGER(IKIND), PARAMETER :: lenw= limit*4
  INTEGER(IKIND) :: IErr,Ieval,last, iwork(limit)
  REAL(RKIND), EXTERNAL :: IntegrateBK
  REAL(RKIND) :: RAccuracy,RError,RResult,dd
  REAL(RKIND) :: work(lenw)
  
  dd=1.0!Do I need this? what does it do?
  RAccuracy=0.00000001D0!accuracy of integration
  !use single integration IntegrateBK as an external function of one variable
  !Quadpack integration 0 to infinity
  CALL dqagi(IntegrateBK,ZERO,inf,0,RAccuracy,RResult,RError,Ieval,IErr,&
       limit, lenw, last, iwork, work )
  !The integration required is actually -inf to inf in 2 dimensions. We used symmetry to just do 0 to inf, so multiply by 4
  RResult=RResult*4
  
END SUBROUTINE DoubleIntegrate

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

FUNCTION IntegrateBK(Sy) 

  USE MyNumbers
  USE WriteToScreen

  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara
  USE BlochPara

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IErr,Ieval
  INTEGER(IKIND), PARAMETER :: inf=1
  INTEGER(IKIND), PARAMETER :: limit=500
  INTEGER(IKIND), PARAMETER :: lenw= limit*4
  REAL(RKIND), EXTERNAL :: BirdKing
  REAL(RKIND) :: RAccuracy,RError,IntegrateBK,Sy
  INTEGER(IKIND) last, iwork(limit)
  REAL(RKIND) work(lenw)

  !RSprimeY is passed into BirdKing as a global variable since we can't integrate a function of 2 variables with dqagi
  RSprimeY=Sy
  RAccuracy=0.00000001D0!accuracy of integration
  !use BirdKing as an external function of one variable
  !Quadpack integration 0 to infinity
  CALL dqagi(BirdKing,ZERO,inf,0,RAccuracy,IntegrateBK,RError,Ieval,IErr,&
       limit, lenw, last, iwork, work )
  
END FUNCTION IntegrateBK

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!Defines a Bird & King integrand to calculate an absorptive scattering factor 
FUNCTION BirdKing(RSprimeX)
  !From Bird and King, Acta Cryst A46, 202 (1990)
  !ICurrentZ is atomic number, global variable
  !RCurrentB is Debye-Waller constant b=8*pi*<u^2>, where u is mean square thermal vibration amplitude in Angstroms, global variable
  !RCurrentGMagnitude is magnitude of scattering vector in 1/A (NB exp(-i*g.r), physics negative convention, global variable
  !RSprime is dummy parameter for integration [s'x s'y]
  !NB can't print from here as it is called EXTERNAL in Integrate
  USE MyNumbers
  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara
  USE BlochPara
  
  IMPLICIT NONE
  
  INTEGER(IKIND) :: ind
  REAL(RKIND):: BirdKing,Rs,Rg1,Rg2,RsEff,Kirkland
  REAL(RKIND), INTENT(IN) :: RSprimeX
  REAL(RKIND),DIMENSION(2) :: RGprime
  
  !NB Kirkland scattering factors in optics convention
  RGprime=2*TWOPI*(/RSprimeX,RSprimeY/)
  !Since [s'x s'y]  is a dummy parameter for integration I can assign s'x //g
  Rg1=SQRT( (RCurrentGMagnitude/2+RGprime(1))**2 + RGprime(2)**2 )
  Rg2=SQRT( (RCurrentGMagnitude/2-RGprime(1))**2 + RGprime(2)**2 )
  RsEff=RSprimeX**2+RSprimeY**2-RCurrentGMagnitude**2/(16*TWOPI**2)
  BirdKing=Kirkland(Rg1)*Kirkland(Rg2)*(1-EXP(-2*RCurrentB*RsEff ) )
  
END FUNCTION BirdKing

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!Returns a Kirkland scattering factor 
FUNCTION Kirkland(Rg)
  !From Appendix C of Kirkland, "Advanced Computing in Electron Microscopy", 2nd ed.
  !ICurrentZ is atomic number, passed as a global variable
  !Rg is magnitude of scattering vector in 1/A (NB exp(-i*g.r), physics negative convention), global variable
  !Kirkland scattering factor is in Angstrom units
  USE MyNumbers
  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara
  USE BlochPara
  
  IMPLICIT NONE
  
  INTEGER(IKIND) :: ind,IErr
  REAL(RKIND) :: Kirkland,Ra,Rb,Rc,Rd,Rq,Rg

  !NB Kirkland scattering factors are calculated in the optics convention exp(2*pi*i*q.r)
  Rq=Rg/TWOPI
  Kirkland=ZERO;
  !Equation C.15
  DO ind = 1,3
    Ra=RScattFactors(ICurrentZ,ind*2-1);
    Rb=RScattFactors(ICurrentZ,ind*2);
    Rc=RScattFactors(ICurrentZ,ind*2+5);
    Rd=RScattFactors(ICurrentZ,ind*2+6);
    Kirkland = Kirkland + Ra/((Rq**2)+Rb)+Rc*EXP(-(Rd*Rq**2));
  END DO
  
END FUNCTION Kirkland

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!Returns a PseudoAtom scattering factor 
SUBROUTINE PseudoFac(CFpseudo,i,j,k,IErr)
  !Reads a scattering factor from the kth Stewart pseudoatom in CPseudoScatt 
  !RCurrentGMagnitude is passed as a global variable
  !IPsize is the size, RPscale the scale factor, of the matrix holding the scattering factor, global variable
  !i and j give the location of the g-vector in the appropriate matrices
  USE MyNumbers
  USE CConst; USE IConst
  USE IPara; USE RPara; USE CPara
  USE BlochPara
  
  IMPLICIT NONE
  
  INTEGER(IKIND) :: i,j,k,Ix,Iy,IErr
  REAL(RKIND) :: Rx,Ry,Rfx,Rfy,f11,f12,f21,f22,a,b,c,d,RrealF,RimagF
  COMPLEX(CKIND) :: CFpseudo

  Rx=0.5+REAL(IPsize/2)+RgMatrix(i,j,1)/RPscale!fft has the origin at [0.5+IPsize/2,0.5+IPsize/2],
  Ry=0.5+REAL(IPsize/2)+RgMatrix(i,j,2)/RPscale!the 0.5 is because the origin is between pixels in an image with an even number of pixels
  Ix=FLOOR(Rx)
  Rfx=REAL(Ix)
  Iy=FLOOR(Ry)
  Rfy=REAL(Iy)
  IF ( (Ix.LE.0).OR.(Ix.GE.(IPsize-1)).OR.(Iy.LE.0).OR.(Iy.GE.(IPsize-1))) THEN!g vector is out of range of the fft
    CFpseudo=CZERO
  ELSE!Find the pixel corresponding to g
    !linear interpolation - CPsuedoScatt oscillates in sign every pixel so do it with ABS and add the sign of the pixel in later
    f11=ABS(AIMAG(CPseudoScatt(Ix,Iy,k)))
    f12=ABS(AIMAG(CPseudoScatt(Ix,Iy+1,k)))
    f21=ABS(AIMAG(CPseudoScatt(Ix+1,Iy,k)))
    f22=ABS(AIMAG(CPseudoScatt(Ix+1,Iy+1,k)))
    d=(f11-f12-f21+f22)/(RPScale*RPScale)
    c=(f11-f12)/RPScale-d*Rfx
    b=(f11-f21)/RPScale-d*Rfy
    a=f11-b*Rfx-c*Rfy-d*Rfx*Rfy
    RimagF=(a+b*Rx+c*Ry+d*Rx*Ry)*SIGN(ONE,AIMAG(CPseudoScatt(NINT(Rx),NINT(Ry),k)))
    f11=ABS(REAL(CPseudoScatt(Ix,Iy,k)))
    f12=ABS(REAL(CPseudoScatt(Ix,Iy+1,k)))
    f21=ABS(REAL(CPseudoScatt(Ix+1,Iy,k)))
    f22=ABS(REAL(CPseudoScatt(Ix+1,Iy+1,k)))
    d=(f11-f12-f21+f22)/(RPScale*RPScale)
    c=(f11-f12)/RPScale-d*Rfx
    b=(f11-f21)/RPScale-d*Rfy
    a=f11-b*Rfx-c*Rfy-d*Rfx*Rfy
    RrealF=(a+b*Rx+c*Ry+d*Rx*Ry)*SIGN(ONE,REAL(CPseudoScatt(NINT(Rx),NINT(Ry),k)))
    CFpseudo=CMPLX(RrealF,RimagF)
  END IF
  IF(IWriteFLAG.EQ.3.AND.my_rank.EQ.0) PRINT*,"Pseudoatom x,y",Ix,Iy,":",CFpseudo

END SUBROUTINE PseudoFac