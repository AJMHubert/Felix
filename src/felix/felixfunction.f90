!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!
! Felix
!
! Richard Beanland, Keith Evans & Rudolf A Roemer
!
! (C) 2013-17, all rights reserved
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
!  Felix is free software: you can redistribute it and/or modify
!  it under the terms of the GNU General Public License as published by
!  the Free Software Foundation, either version 3 of the License, or
!  (at your option) any later version.
!  
!  Felix is distributed in the hope that it will be useful,
!  but WITHOUT ANY WARRANTY; without even the implied warranty of
!  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!  GNU General Public License for more details.
!  
!  You should have received a copy of the GNU General Public License
!  along with Felix.  If not, see <http://www.gnu.org/licenses/>.
!
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
! $Id: Felixrefine.f90,v 1.89 2014/04/28 12:26:19 phslaz Exp $
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

! All procedures conatained in this file:
! SimulateAndFit( )                               ---
! FelixFunction( )                                ---
! CalculateFigureofMeritandDetermineThickness( )  ---
! UpdateVariables( )                              ---
! PrintVariables( )                               ---
! UpdateStructureFactors( )                       semi-obselete
! ConvertVectorMovementsIntoAtomicCoordinates( )  semi-obselete
! BlurG( )                                        ---
! Parabo3( )                                      ---


!>
!! Procedure-description: Simulate and fit
!!
!! Major-Authors: Richard Beanland (2016)
!!  
SUBROUTINE SimulateAndFit(RIndependentVariable,Iter,IExitFLAG,IErr)

  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels
  USE message_mod
  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IErr,IExitFLAG,IThicknessIndex,ind,jnd
  REAL(RKIND),DIMENSION(INoOfVariables) :: RIndependentVariable
  INTEGER(IKIND),INTENT(INOUT) :: Iter
  COMPLEX(CKIND),DIMENSION(nReflections,nReflections) :: CUgMatDummy
  CHARACTER*200 :: SFormat,SPrintString

  CALL message(LM,"Iteration ",Iter)
  
  IF (IRefineMode(1).EQ.1) THEN  !Ug refinement; update structure factors 
    !Dummy Matrix to contain new iterative values
    CUgMatDummy = CZERO    !NB these are Ug's without absorption
    jnd=1
    !work through the Ug's to update
    DO ind = 1+IUgOffset,INoofUgs+IUgOffset
    !Don't update components smaller than RTolerance: 3 possible types of Ug, complex, real and imaginary
    IF ( (ABS(REAL(CUniqueUg(ind),RKIND)).GE.RTolerance).AND.&
         (ABS(AIMAG(CUniqueUg(ind))).GE.RTolerance)) THEN!use both real and imag parts
       CUniqueUg(ind)=CMPLX(RIndependentVariable(jnd),RIndependentVariable(jnd+1))
       jnd=jnd+2
    ELSEIF ( ABS(AIMAG(CUniqueUg(ind))).LT.RTolerance ) THEN!use only real part
       CUniqueUg(ind)=CMPLX(RIndependentVariable(jnd),ZERO)
       jnd=jnd+1
    ELSEIF ( ABS(REAL(CUniqueUg(ind),RKIND)).LT.RTolerance ) THEN!use only imag part
       CUniqueUg(ind)=CMPLX(ZERO,RIndependentVariable(jnd))
       jnd=jnd+1
    ELSE!should never happen
       CALL message(LS,"Warning - zero structure factor!")
       CALL message(LS,dbg_default,"A CUniqueUg element has value = ",CUniqueUg(IEquivalentUgKey(ind)))
       CALL message(LS,"element number = ",ind)
       IErr=1
    END IF

    !Update the Ug matrix for this Ug
    WHERE(ISymmetryRelations.EQ.IEquivalentUgKey(ind))
       CUgMatDummy = CUniqueUg(ind)
    END WHERE
    WHERE(ISymmetryRelations.EQ.-IEquivalentUgKey(ind))
       CUgMatDummy = CONJG(CUniqueUg(ind))
    END WHERE
    END DO
    !put the changes into CUgMatNoAbs
    WHERE(ABS(CUgMatDummy).GT.TINY)
      CUgMatNoAbs = CUgMatDummy
    END WHERE
    CALL Absorption(IErr)
    IF( IErr.NE.0 ) THEN
      PRINT*,"Error:SimulateAndFit(",my_rank,")error in Absorption"
      RETURN
    END IF
    IF (IAbsorbFLAG.EQ.1) THEN!proportional absorption
     RAbsorptionPercentage = RIndependentVariable(jnd)
    END IF
  ELSE  !everything else
    !Update variables
    CALL UpdateVariables(RIndependentVariable,IErr)
    IF( IErr.NE.0 ) THEN
      PRINT*,"Error:SimulateAndFit(",my_rank,")error in UpdateVariables"
      RETURN
    END IF
    IF (IRefineMode(8).EQ.1) THEN!convergence angle
       !recalculate k-vectors
       RDeltaK = RMinimumGMag*RConvergenceAngle/REAL(IPixelCount,RKIND)
       !IF (my_rank.EQ.0) THEN
       !  WRITE(SFormat,*) "(I5.1,1X,F13.9,1X,F13.9,1X)"
       !  OPEN(UNIT=IChOutSimplex,file='IterationLog.txt',form='formatted',status='unknown',position='append')
       !  WRITE(UNIT=IChOutSimplex,FMT=SFormat) Iter,RFigureofMerit,RConvergenceAngle
       !  CLOSE(IChOutSimplex)
       !END IF
     END IF
    !recalculate unit cell
    CALL UniqueAtomPositions(IErr)!This is being called unnecessarily for some refinement modes
    IF( IErr.NE.0 ) THEN
      PRINT*,"Error:SimulateAndFit(",my_rank,")error in UniqueAtomPositions"
      RETURN
    END IF
    !Update scattering matrix
    CALL UpdateUgMatrix(IErr)
    CALL Absorption (IErr)
    IF( IErr.NE.0 ) THEN
      PRINT*,"Error:felixfunction(",my_rank,")error in UpdateUgMatrix"
      RETURN
    END IF
  END IF

  IF (my_rank.EQ.0) THEN!send current values to screen
     CALL PrintVariables(IErr)
     IF( IErr.NE.0 ) THEN
        PRINT*,"Error:SimulateAndFit(",my_rank,")error in PrintVariables"
        RETURN
     END IF
  END IF
  RSimulatedPatterns = ZERO!Reset simulation
  CALL FelixFunction(IErr) ! Simulate !!  
  IF( IErr.NE.0 ) THEN
     PRINT*,"Error:SimulateAndFit(",my_rank,")error in FelixFunction"
     RETURN
  END IF
  IF (IMethodFLAG.NE.1) Iter=Iter+1!iterate for methods other than simplex
  IF(my_rank.EQ.0) THEN
    IF (ISimFLAG.EQ.0) THEN!Only calculate figure of merit if we are refining
      CALL CalculateFigureofMeritandDetermineThickness(Iter,IThicknessIndex,IErr)
      IF( IErr.NE.0 ) THEN
        PRINT*,"Error:SimulateAndFit(0) error",IErr,"in CalculateFigureofMeritandDetermineThickness"
        RETURN
      END IF
    END IF
    !Write current variable list and fit to IterationLog.txt
    CALL WriteOutVariables(Iter,IErr)
    IF( IErr.NE.0 ) THEN
      PRINT*,"Error:WriteIterationOutput(0) error in WriteOutVariables"
      RETURN
    END IF
    !write images to disk every IPrint iterations, or when finished
    IF(IExitFLAG.EQ.1.OR.(Iter.GE.(IPreviousPrintedIteration+IPrint))) THEN
      CALL WriteIterationOutput(Iter,IThicknessIndex,IExitFLAG,IErr)
      IF( IErr.NE.0 ) THEN
        PRINT*,"Error:SimulateAndFit(0) error in WriteIterationOutput"
        RETURN
      END IF
      IPreviousPrintedIteration = Iter!reset iteration counter
    END IF
  END IF

  !=====================================Send the fit index to all cores
  CALL MPI_BCAST(RFigureofMerit,1,MPI_DOUBLE_PRECISION,0,MPI_COMM_WORLD,IErr)
  !=====================================

END SUBROUTINE SimulateAndFit

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




!>
!! Procedure-description: Felixfunction
!!
!! Major-Authors: Keith Evans (2014), Richard Beanland (2016)
!!  
SUBROUTINE FelixFunction(IErr)

  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels
  USE message_mod
  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IErr,ind,jnd,knd,pnd,IIterationFLAG
  INTEGER(IKIND) :: IAbsorbTag = 0
  REAL(RKIND),DIMENSION(:,:,:),ALLOCATABLE :: RFinalMontageImageRoot
  REAL(RKIND),DIMENSION(:,:),ALLOCATABLE :: RTempImage 

  !Reset simuation--------------------------------------------------------------------  
  RIndividualReflections = ZERO
  IMAXCBuffer = 200000!RB what are these?
  IPixelComputed= 0

  !Simulation (different local pixels for each core)--------------------------------------------------------------------  
  CALL message(LM,"Bloch wave calculation...")
  DO knd = ILocalPixelCountMin,ILocalPixelCountMax,1
    jnd = IPixelLocations(knd,1)
    ind = IPixelLocations(knd,2)
    CALL BlochCoefficientCalculation(ind,jnd,knd,ILocalPixelCountMin,IErr)
    IF( IErr.NE.0 ) THEN
      PRINT*,"Error:Felixfunction(",my_rank,") error in BlochCofficientCalculation"
      RETURN
    END IF
  END DO

  !=====================================!MPI gatherv into RSimulatedPatterns--------------------------------------------------------------------  
  CALL MPI_GATHERV(RIndividualReflections,SIZE(RIndividualReflections),MPI_DOUBLE_PRECISION,&
       RSimulatedPatterns,ICount,IDisplacements,MPI_DOUBLE_PRECISION,&
       root,MPI_COMM_WORLD,IErr)
  !=====================================
  IF( IErr.NE.0 ) THEN
     PRINT*,"Error:Felixfunction(",my_rank,")error",IErr,"in MPI_GATHERV"
     RETURN
  END IF
  !put 1D array RSimulatedPatterns into 2D image RImageSimi
  !remember dimensions of RSimulatedPatterns(INoOfLacbedPatterns,IThicknessCount,IPixelTotal)
  !and RImageSimi(width, height,INoOfLacbedPatterns,IThicknessCount )
  RImageSimi = ZERO
  ind = 0
  DO jnd = 1,2*IPixelCount
     DO knd = 1,2*IPixelCount
        ind = ind+1
        RImageSimi(jnd,knd,:,:) = RSimulatedPatterns(:,:,ind)
     END DO
  END DO

  !Gaussian blur to match experiment using global variable RBlurRadius
  IF (RBlurRadius.GT.TINY) THEN
     ALLOCATE(RTempImage(2*IPixelCount,2*IPixelCount),STAT=IErr)
     DO ind=1,INoOfLacbedPatterns
        DO jnd=1,IThicknessCount
           RTempImage = RImageSimi(:,:,ind,jnd)
           CALL BlurG(RTempImage,IErr)
           RImageSimi(:,:,ind,jnd) = RTempImage 
        END DO
     END DO
  END IF

  !We have done at least one simulation now
  IInitialSimulationFLAG=0

END SUBROUTINE FelixFunction

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




!>
!! Procedure-description: Calculate figure of merit and determine Thickness, 
!! involving image processing and correlation type.
!!
!! Major-Authors: Keith Evans (2014), Richard Beanland (2016)
!!  
SUBROUTINE CalculateFigureofMeritandDetermineThickness(Iter,IBestThicknessIndex,IErr)
  !NB core 0 only
  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels
  USE message_mod
  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: ind,jnd,knd,IErr,IThickness,hnd,Iter
  INTEGER(IKIND),DIMENSION(INoOfLacbedPatterns) :: IBestImageThicknessIndex
  INTEGER(IKIND),INTENT(OUT) :: IBestThicknessIndex
  REAL(RKIND),DIMENSION(2*IPixelCount,2*IPixelCount) :: RSimulatedImage,RExperimentalImage
  REAL(RKIND),DIMENSION(:,:),ALLOCATABLE :: RMaskImage
  REAL(RKIND) :: RTotalCorrelation,RBestTotalCorrelation,RImageCorrelation,RBestThickness,&
       PhaseCorrelate,Normalised2DCrossCorrelation,MaskedCorrelation,ResidualSumofSquares,&
       RThicknessRange,Rradius
  REAL(RKIND),DIMENSION(INoOfLacbedPatterns) :: RBestCorrelation
  CHARACTER*200 :: SPrintString
  CHARACTER*20 :: Snum       

  IF (ICorrelationFLAG.EQ.3) THEN !Memory saving  only allocate mask if needed
    ALLOCATE(RMaskImage(2*IPixelCount,2*IPixelCount),STAT=IErr)
  END IF
  RBestCorrelation = TEN ! The best correlation for each image will go in here, initialise at the maximum value
  RBestTotalCorrelation = TEN !The best mean of all correlations
  IBestImageThicknessIndex = 1 !The thickness with the lowest figure of merit for each image
  DO jnd = 1,IThicknessCount
    RTotalCorrelation = ZERO !The sum of all individual correlations, initialise at 0
    DO ind = 1,INoOfLacbedPatterns
      RSimulatedImage = RImageSimi(:,:,ind,jnd)
      RExperimentalImage = RImageExpi(:,:,ind)
      IF (ICorrelationFLAG.EQ.3) THEN!masked correltion, update mask
        RMaskImage=RImageMask(:,:,ind)
      END IF
      
      !image processing----------------------------------- 
      SELECT CASE (IImageProcessingFLAG)
        !CASE(0)!no processing
      CASE(1)!square root before perfoming correlation
        RSimulatedImage=SQRT(RSimulatedImage)
        RExperimentalImage=SQRT(RImageExpi(:,:,ind))
      CASE(2)!log before performing correlation
        WHERE (RSimulatedImage.GT.TINY**2)
          RSimulatedImage=LOG(RSimulatedImage)
        ELSEWHERE
          RSimulatedImage = TINY**2
        END WHERE
        WHERE (RExperimentalImage.GT.TINY**2)
          RExperimentalImage = LOG(RImageExpi(:,:,ind))
        ELSEWHERE
          RExperimentalImage =  TINY**2
        END WHERE
      
      END SELECT
      
      !Correlation type-----------------------------------
      SELECT CASE (ICorrelationFLAG)
        CASE(0) ! Phase Correlation
          RImageCorrelation=ONE-& ! NB Perfect Correlation = 0 not 1
                PhaseCorrelate(RSimulatedImage,RExperimentalImage,&
                IErr,2*IPixelCount,2*IPixelCount)
        CASE(1) ! Residual Sum of Squares (Non functional)
          RImageCorrelation = ResidualSumofSquares(&
                RSimulatedImage,RImageExpi(:,:,ind),IErr)
        CASE(2) ! Normalised Cross Correlation
          RImageCorrelation = ONE-& ! NB Perfect Correlation = 0 not 1
                Normalised2DCrossCorrelation(RSimulatedImage,RExperimentalImage,IErr)
        CASE(3) ! Masked Cross Correlation
          IF (Iter.LE.0) THEN !we are in baseline sim or simplex initialisation: do a normalised2D CC
            RImageCorrelation = ONE-&
                  Normalised2DCrossCorrelation(RSimulatedImage,RExperimentalImage,IErr)   
          ELSE !we are refining: do a masked CC
            RImageCorrelation = ONE-& ! NB Perfect Correlation = 0 not 1
                  MaskedCorrelation(RSimulatedImage,RExperimentalImage,RMaskImage,IErr)
          END IF
      END SELECT

      CALL message(LL,dbg6,"For Pattern ",ind,", thickness ",jnd)
      CALL message(LL,dbg6,"  the FoM = ",RImageCorrelation)
      

      !Update best image correlation values if we need to     
      IF(RImageCorrelation.LT.RBestCorrelation(ind)) THEN
        RBestCorrelation(ind) = RImageCorrelation
        IBestImageThicknessIndex(ind) = jnd
      END IF
      RTotalCorrelation = RTotalCorrelation + RImageCorrelation
    END DO
    
    !The best total correlation
    RTotalCorrelation=RTotalCorrelation/REAL(INoOfLacbedPatterns,RKIND)

    CALL message(LL,dbg6,"For thickness ",jnd)
    CALL message(LL,dbg6,"  the mean correlation = ",RTotalCorrelation)

    IF(RTotalCorrelation.LT.RBestTotalCorrelation) THEN
      RBestTotalCorrelation = RTotalCorrelation
      IBestThicknessIndex = jnd
    END IF
  END DO

  

  !!The figure of merit, global variable
  RFigureofMerit = RBestTotalCorrelation
     !Alternative: assume that the best thickness is given by the mean of individual thicknesses  
     !  IBestThicknessIndex = SUM(IBestImageThicknessIndex)/INoOfLacbedPatterns
     !  RBestThickness = RInitialThickness + (IBestThicknessIndex-1)*RDeltaThickness
     !  RFigureofMerit = SUM(RBestCorrelation*RWeightingCoefficients)/&
     !     REAL(INoOfLacbedPatterns,RKIND)
  !Output to screen-----------------------------------

  RBestThickness = RInitialThickness +(IBestThicknessIndex-1)*RDeltaThickness
  RThicknessRange=( MAXVAL(IBestImageThicknessIndex)-MINVAL(IBestImageThicknessIndex) )*RDeltaThickness


  CALL message(LM,"Figure of merit ",RBestTotalCorrelation)
  CALL message(LM,"Specimen thickness (Angstroms) = ",NINT(RBestThickness))
  CALL message(LM,"Thickness range (Angstroms) = ",NINT(RThicknessRange))

  RETURN
  !10 RETURN !for debug

END SUBROUTINE CalculateFigureofMeritandDetermineThickness

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



!>
!! Procedure-description: Fill the indepedent value array with values 
!!
!! Major-Authors: Keith Evans (2014), Richard Beanland (2016)
!!  
SUBROUTINE UpdateVariables(RIndependentVariable,IErr)

  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IVariableType,IVectorID,IAtomID,IErr,ind
  REAL(RKIND),DIMENSION(INoOfVariables),INTENT(IN) :: RIndependentVariable

  IF(IRefineMode(2).EQ.1) THEN     
     RBasisAtomPosition = RInitialAtomPosition !RB is this redundant? 
  END IF

  DO ind = 1,INoOfVariables
    IVariableType = IIterativeVariableUniqueIDs(ind,2)
    SELECT CASE (IVariableType)
    CASE(1) !A: structure factor refinement, do in UpdateStructureFactors
      
    CASE(2)
      !CALL ConvertVectorMovementsIntoAtomicCoordinates(ind,RIndependentVariable,IErr)
      !The vector being used
      IVectorID = IIterativeVariableUniqueIDs(ind,3)
      !The atom being moved
      IAtomID = IAllowedVectorIDs(IVectorID)
      !Change in position
      RBasisAtomPosition(IAtomID,:) = RBasisAtomPosition(IAtomID,:) + &
             RIndependentVariable(ind)*RAllowedVectors(IVectorID,:)
    CASE(3)
      RBasisOccupancy(IIterativeVariableUniqueIDs(ind,3))=RIndependentVariable(ind)
 
    CASE(4)
      RBasisIsoDW(IIterativeVariableUniqueIDs(ind,3))=RIndependentVariable(ind)
    CASE(5)
      RAnisotropicDebyeWallerFactorTensor(&
           IIterativeVariableUniqueIDs(ind,3),&
           IIterativeVariableUniqueIDs(ind,4),&
           IIterativeVariableUniqueIDs(ind,5)) = & 
           RIndependentVariable(ind)
    CASE(6)
      SELECT CASE(IIterativeVariableUniqueIDs(ind,3))
      CASE(1)
        RLengthX = RIndependentVariable(ind)
      CASE(2)
        RLengthY = RIndependentVariable(ind)
      CASE(3)
        RLengthZ = RIndependentVariable(ind)
      END SELECT
    CASE(7)
      SELECT CASE(IIterativeVariableUniqueIDs(ind,3))
      CASE(1)
        RAlpha = RIndependentVariable(ind)
      CASE(2)
        RBeta = RIndependentVariable(ind)
      CASE(3)
        RGamma = RIndependentVariable(ind)
      END SELECT
    CASE(8)
      RConvergenceAngle = RIndependentVariable(ind)
    CASE(9)
      RAbsorptionPercentage = RIndependentVariable(ind)
    CASE(10)
      RAcceleratingVoltage = RIndependentVariable(ind)
    CASE(11)
      RRSoSScalingFactor = RIndependentVariable(ind)
    END SELECT
  END DO

END SUBROUTINE UpdateVariables

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



!>
!! Procedure-description: Print variables
!!
!! Major-Authors: Keith Evans (2014), Richard Beanland (2016)
!! 
SUBROUTINE PrintVariables(IErr)

  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels
  USE message_mod
  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IErr,ind,IVariableType,jnd,knd
  REAL(RKIND),DIMENSION(3) :: RCrystalVector
  CHARACTER*200 :: SPrintString

  RCrystalVector = [RLengthX,RLengthY,RLengthZ]

  DO ind = 1,IRefinementVariableTypes
    IF (IRefineMode(ind).EQ.1) THEN
      SELECT CASE(ind)
      CASE(1)
        IF (IAbsorbFLAG.EQ.1) THEN!proportional absorption
          CALL message(LS,"Current Absorption ",RAbsorptionPercentage)
        END IF
        CALL message(LS,"Current Structure Factors nm^-2: amplitude, phase (deg)")!RB should also put in hkl here
        !DO jnd = 1+IUgOffset,INoofUgs+IUgOffset
        !  WRITE(SPrintString,FMT='(2(1X,F7.3),2X,A1,1X,F6.3,1X,F6.2)') 100*CUniqueUg(jnd),":",&
        !       ABS(CUniqueUg(jnd)),180*ATAN2(AIMAG(CUniqueUg(jnd)),REAL(CUniqueUg(jnd)))/PI
        !END DO
        DO jnd = 1+IUgOffset,INoofUgs+IUgOffset
          CALL message(LM,"",100*CUniqueUg(jnd))
          CALL message(LM,"",(/ ABS(CUniqueUg(jnd)),180*ATAN2(AIMAG(CUniqueUg(jnd)),REAL(CUniqueUg(jnd)))/PI /))
        END DO

      CASE(2)
        CALL message(LM,"Current Atomic Coordinates")
        DO jnd = 1,SIZE(RBasisAtomPosition,DIM=1)
          CALL message(LM,SBasisAtomLabel(jnd),RBasisAtomPosition(jnd,:))
        END DO

      CASE(3)
        CALL message(LM, "Current Atomic Occupancy")
        DO jnd = 1,SIZE(RBasisOccupancy,DIM=1)
          CALL message(LM, SBasisAtomLabel(jnd),RBasisOccupancy(jnd))
        END DO

      CASE(4)
        CALL message(LM, "Current Isotropic Debye Waller Factors")
        DO jnd = 1,SIZE(RBasisIsoDW,DIM=1)
          CALL message(LM, SBasisAtomLabel(jnd),RBasisIsoDW(jnd))
        END DO

      CASE(5)
        CALL message(LM,"Current Anisotropic Debye Waller Factors")
        DO jnd = 1,SIZE(RAnisotropicDebyeWallerFactorTensor,DIM=1)
          CALL message(LM, "Tensor index = ", jnd) 
          CALL message(LM, SBasisAtomLabel(jnd),RAnisotropicDebyeWallerFactorTensor(jnd,1:3,:) )
        END DO

      CASE(6)
        CALL message(LM, "Current Unit Cell Parameters", (/ RLengthX,RLengthY,RLengthZ /) )

      CASE(7)
        CALL message(LM, "Current Unit Cell Angles", (/ RAlpha,RBeta,RGamma /) )

      CASE(8)
        CALL message(LM, "Current Convergence Angle: ", RConvergenceAngle )

      CASE(9)
        CALL message(LM, "Current Absorption Percentage", RAbsorptionPercentage )

      CASE(10)
        CALL message(LM, "Current Accelerating Voltage", RAcceleratingVoltage )

      CASE(11)
        CALL message(LM, "Current Residual Sum of Squares Scaling Factor", RRSoSScalingFactor )

      END SELECT
    END IF
  END DO

END SUBROUTINE PrintVariables

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



!>
!! Procedure-description: Update structure factors
!!
!! Major-Authors: Keith Evans (2014), Richard Beanland (2016)
!! 
SUBROUTINE UpdateStructureFactors(RIndependentVariable,IErr)

  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels
  USE message_mod
  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IErr,ind,jnd
  REAL(RKIND),DIMENSION(INoOfVariables),INTENT(IN) :: RIndependentVariable
  CHARACTER*200 :: SPrintString

  !NB these are Ug's without absorption
  jnd=1
  DO ind = 1+IUgOffset,INoofUgs+IUgOffset!=== temp changes so real part only***
    IF ( (ABS(REAL(CUniqueUg(ind),RKIND)).GE.RTolerance).AND.&!===
        (ABS(AIMAG(CUniqueUg(ind))).GE.RTolerance)) THEN!use both real and imag parts!===
      CUniqueUg(ind)=CMPLX(RIndependentVariable(jnd),RIndependentVariable(jnd+1))!===
      jnd=jnd+2!===
    ELSEIF ( ABS(AIMAG(CUniqueUg(ind))).LT.RTolerance ) THEN!use only real part!===
      CUniqueUg(ind)=CMPLX(RIndependentVariable(jnd),ZERO)!===
      !===      CUniqueUg(ind)=CMPLX(RIndependentVariable(jnd),AIMAG(CUniqueUg(ind)))!===replacement line, delete to revert
      jnd=jnd+1
    ELSEIF ( ABS(REAL(CUniqueUg(ind),RKIND)).LT.RTolerance ) THEN!===use only imag part
      CUniqueUg(ind)=CMPLX(ZERO,RIndependentVariable(jnd))!===
      jnd=jnd+1!===
    ELSE!should never happen!===
      !todo - warning grouped with errors?
      CALL message(LS, "Warning - zero structure factor! At element = ",ind)
      CALL message(LS, "     CUniqueUg vector element value = ", CUniqueUg(IEquivalentUgKey(ind)))!===
    END IF!===
  END DO
  RAbsorptionPercentage = RIndependentVariable(jnd)!===

END SUBROUTINE UpdateStructureFactors

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



!>
!! Procedure-description: Convert vector movements into atomic coordinates
!!
!! Major-Authors: Keith Evans (2014), Richard Beanland (2016)
!! 
SUBROUTINE ConvertVectorMovementsIntoAtomicCoordinates(IVariableID,RIndependentVariable,IErr)
  !RB this is now redundant, moved up to Update Variables
  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IErr,ind,jnd,IVariableID,IVectorID,IAtomID
  REAL(RKIND),DIMENSION(INoOfVariables),INTENT(IN) :: RIndependentVariable

!!$  Use IVariableID to determine which vector is being applied (IVectorID)
  IVectorID = IIterativeVariableUniqueIDs(IVariableID,3)
!!$  Use IVectorID to determine which atomic coordinate the vector is to be applied to (IAtomID)
  IAtomID = IAllowedVectorIDs(IVectorID)
!!$  Use IAtomID to applied the IVectodID Vector to the IAtomID atomic coordinate
  RBasisAtomPosition(IAtomID,:) = RBasisAtomPosition(IAtomID,:) + &
       RIndependentVariable(IVariableID)*RAllowedVectors(IVectorID,:)

END SUBROUTINE ConvertVectorMovementsIntoAtomicCoordinates

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



!>
!! Procedure-description: Performs a 2D Gaussian blur on the input image using 
!! global variable RBlurRadius and renormalises the output image to have the
!! same min and max as the input image
!!
!! Major-Authors: Richard Beanland (2016)
!! 
SUBROUTINE BlurG(RImageToBlur,IErr)

  USE MyNumbers

  USE CConst; USE IConst; USE RConst
  USE IPara; USE RPara; USE SPara; USE CPara
  USE BlochPara

  USE IChannels

  USE MPI
  USE MyMPI

  IMPLICIT NONE

  INTEGER(IKIND) :: IErr,ind,jnd,IKernelRadius,IKernelSize
  REAL(RKIND),DIMENSION(:), ALLOCATABLE :: RGauss1D
  REAL(RKIND),DIMENSION(2*IPixelCount,2*IPixelCount) :: RImageToBlur,RTempImage,RShiftImage
  REAL(RKIND) :: Rind,Rsum,Rmin,Rmax

  !get min and max of input image
  Rmin=MINVAL(RImageToBlur)
  Rmax=MAXVAL(RImageToBlur)

  !set up a 1D kernel of appropriate size  
  IKernelRadius=NINT(3*RBlurRadius)
  ALLOCATE(RGauss1D(2*IKernelRadius+1),STAT=IErr)!ffs
  Rsum=0
  DO ind=-IKernelRadius,IKernelRadius
     Rind=REAL(ind)
     RGauss1D(ind+IKernelRadius+1)=EXP(-(Rind**2)/((2*RBlurRadius)**2))
     Rsum=Rsum+RGauss1D(ind+IKernelRadius+1)
  END DO
  RGauss1D=RGauss1D/Rsum!normalise
  RTempImage=RImageToBlur*0_RKIND;!reset the temp image

  !apply the kernel in direction 1
  DO ind = -IKernelRadius,IKernelRadius
     IF (ind.LT.0) THEN
        RShiftImage(1:2*IPixelCount+ind,:)=RImageToBlur(1-ind:2*IPixelCount,:)
        DO jnd = 1,1-ind!edge fill on right
           RShiftImage(2*IPixelCount-jnd+1,:)=RImageToBlur(2*IPixelCount,:)
        END DO
     ELSE
        RShiftImage(1+ind:2*IPixelCount,:)=RImageToBlur(1:2*IPixelCount-ind,:)
        DO jnd = 1,1+ind!edge fill on left
           RShiftImage(jnd,:)=RImageToBlur(1,:)
        END DO
     END IF
     RTempImage=RTempImage+RShiftImage*RGauss1D(ind+IKernelRadius+1)
  END DO

  !make the 1D blurred image the input for the next direction
  RImageToBlur=RTempImage;
  RTempImage=RImageToBlur*0_RKIND;!reset the temp image

  !apply the kernel in direction 2  
  DO ind = -IKernelRadius,IKernelRadius
     IF (ind.LT.0) THEN
        RShiftImage(:,1:2*IPixelCount+ind)=RImageToBlur(:,1-ind:2*IPixelCount)
        DO jnd = 1,1-ind!edge fill on bottom
           RShiftImage(:,2*IPixelCount-jnd+1)=RImageToBlur(:,2*IPixelCount)
        END DO
     ELSE
        RShiftImage(:,1+ind:2*IPixelCount)=RImageToBlur(:,1:2*IPixelCount-ind)
        DO jnd = 1,1+ind!edge fill on top
           RShiftImage(:,jnd)=RImageToBlur(:,1)
        END DO
     END IF
     RTempImage=RTempImage+RShiftImage*RGauss1D(ind+IKernelRadius+1)
  END DO
  DEALLOCATE(RGauss1D,STAT=IErr)

  !set intensity range of outpt image to match that of the input image
  RTempImage=RTempImage-MINVAL(RTempImage)
  RTempImage=RTempImage*(Rmax-Rmin)/MAXVAL(RTempImage)+Rmin
  !return the blurred image
  RImageToBlur=RTempImage;

END SUBROUTINE BlurG

!!$  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




!>
!! Procedure-description: Input is a vector Rx with three x-coordinates and 
!! Ry with three y-coordinates. Output is the x- and y-coordinate of the vertex
!! of the fitted parabola, Rxv Ryv. Using Cramer's rules to solve the system of
!! equations to give Ra(x^2)+Rb(x)+Rc=(y)
!!
!! Major-Authors: Richard Beanland (2016)
!! 
SUBROUTINE Parabo3(Rx,Ry,Rxv,Ryv,IErr)

  USE MyNumbers

  IMPLICIT NONE
  
  REAL(RKIND) :: Ra,Rb,Rc,Rd,Rxv,Ryv
  REAL(RKIND),DIMENSION(3) :: Rx,Ry
  INTEGER(IKIND) :: IErr
  
  Rd = Rx(1)*Rx(1)*(Rx(2)-Rx(3)) + Rx(2)*Rx(2)*(Rx(3)-Rx(1)) + Rx(3)*Rx(3)*(Rx(1)-Rx(2))
  Ra =(Rx(1)*(Ry(3)-Ry(2)) + Rx(2)*(Ry(1)-Ry(3)) + Rx(3)*(Ry(2)-Ry(1)))/Rd
  Rb =(Rx(1)*Rx(1)*(Ry(2)-Ry(3)) + Rx(2)*Rx(2)*(Ry(3)-Ry(1)) + Rx(3)*Rx(3)*(Ry(1)-Ry(2)))/Rd
  Rc =(Rx(1)*Rx(1)*(Rx(2)*Ry(3)-Rx(3)*Ry(2)) + Rx(2)*Rx(2)*(Rx(3)*Ry(1)-Rx(1)*Ry(3))&
      +Rx(3)*Rx(3)*(Rx(1)*Ry(2)-Rx(2)*Ry(1)))/Rd
  Rxv = -Rb/(2*Ra);!x-coord
  Ryv = Rc-Rb*Rb/(4*Ra)!y-coord

END SUBROUTINE  Parabo3