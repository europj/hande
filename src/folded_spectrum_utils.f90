module folded_spectrum_utils
!TO DO:
! tau finder
! calculating P__, P_o, Po_

use const

use proc_pointers
use fciqmc_data, only: fold_line, fs_offset


implicit none

! 1) self spawning
!      ___
!     / _ \
!    | / \ |
!     \\.//

! 2) granddaughter spawning
!      __   __ 
!    ./  \./  \.
!
! 3) self spawning
!      __
!    ./  \.
!     \__/
!
! 4) daughter spawning
!     _
!    / \
!    \./____.
!
! 5) daughter spawning
!          _
!         / \
!    .____\./


contains



    subroutine fs_spawner(cdet, parent_sign, nspawn, connection)
        ! Attempt to spawn a new particle on a daughter or granddaughter determinant according to
        ! the fsfciqmc algorithm for a given system
        !
        ! In:
        !    cdet: info on the current determinant (cdet) that we will spawn
        !        from.
        !    parent_sign: sign of the population on the parent determinant (i.e.
        !        either a positive or negative integer).
        ! Out:
        !    nspawn: number of particles spawned.  0 indicates the spawning
        !        attempt was unsuccessful.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are spawned.
        use determinants, only: det_info
        use excitations, only: excit
        use fciqmc_data, only: tau, H00
        use excitations, only: create_excited_det_complete, create_excited_det, get_excitation
        use basis, only: basis_length

        implicit none
        type(det_info), intent(in) :: cdet
        integer, intent(in) :: parent_sign
        integer, intent(out) :: nspawn
        type(excit), intent(out) :: connection

        real(p),parameter      :: P__=0.2, Po_=(1.0-P__)*0.5, P_o=Po_
        real(p),parameter, dimension(3) :: P_double_elt_type =(/P__, Po_, P_o /)

        real(p)          :: choose_double_elt_type
        
        ! P_gen (k|i) and P_gen (j|k)
        real(p)          :: Pgen_ki, Pgen_jk 
        real(p)          :: hmatel_ki, hmatel_jk
        type(excit)      :: connection_ki, connection_jk
        real(p)          :: psuccess, pspawn, pgen, hmatel
        type(det_info)   :: cdet_excit

        integer(i0)      :: f_excit_2(basis_length)


       ! specific to imperial code:
        !      -function that creates an excited determinant (create_excited_det)
        !      -types excit, cdet

        
        
        ! 0. Choose the type of double element you're going to spawn 
        choose_double_elt_type = rng_ptr()
        
        ! **We want to choose the largest probability first, since this will reduce the number of if statement calls, 
        ! **however, the values of P__ etc will ideally be reference-determinant dependent, what is the best way to order this sequence?**


elttype:if(choose_double_elt_type <= P__ ) then
            
            !      __   __ 
            !    ./  \./  \.
            !    i    k    j
            !
            !    i __
            !    ./  \.
            !     \__/ k
            !    j   
            ! 1.1 Generate first random excitation and probability of spawning there from cdet 
            call gen_excit_ptr(cdet, Pgen_ki, connection_ki, hmatel_ki)

            ! 1.2 Generate the second random excitation 
            ! (i)  generate the first excited determinant  
            call create_excited_det_complete(cdet, connection_ki, cdet_excit)



            ! (ii) excite again
            call gen_excit_ptr(cdet_excit, Pgen_jk, connection_jk, hmatel_jk)

            ! 2. Probability of gening...
            pgen = P__ * Pgen_ki * Pgen_jk
            pspawn = tau*abs(hmatel_ki*hmatel_jk)/pgen
            
            ! 3. Attempt spawning.
            psuccess = rng_ptr()

            ! Need to take into account the possibilty of a spawning attempt
            ! producing multiple offspring...
            ! If pspawn is > 1, then we spawn floor(pspawn) as a minimum and 
            ! then spawn a particle with probability pspawn-floor(pspawn).
            nspawn = int(pspawn)
            pspawn = pspawn - nspawn

            if (pspawn > psuccess) nspawn = nspawn + 1

            if (nspawn > 0) then

                ! 4. If H_ij is positive, then the spawned walker is of opposite
                ! sign to the parent, otherwise the spawned walkers if of the same
                ! sign as the parent.
                if (hmatel_ki*hmatel_jk > 0.0_p) then
                    nspawn = -sign(nspawn, parent_sign)
                else
                    nspawn = sign(nspawn, parent_sign)
                end if

            end if

            ! 5. Calculate the excited determinant connection (can be up to degree 4)
            ! (i)   find the second excited determinant bitstring
            call create_excited_det(cdet_excit%f, connection_jk, f_excit_2)
            ! (ii)  calculate the connection to this excited determinant
            connection = get_excitation(cdet%f,f_excit_2)


         !******************* this code does not work in the case of looping back on itself *********************
            ! 5. Calculate the excited determinant (can be up to degree 4)
            ! (i)   add up the number of excitations
!           connection%nexcit = connection_ki%nexcit + connection_jk%nexcit
            ! (ii)  combine the annihilations
!           connection%from_orb(:connection_ki%nexcit) = &
!                               connection_ki%from_orb(:connection_ki%nexcit)

!           connection%from_orb(connection_ki%nexcit+1:connection%nexcit) = &
!                               connection_jk%from_orb(:connection_jk%nexcit)

            ! (iii) combine the creations
!           connection%to_orb(:connection_ki%nexcit) = &
!                               connection_ki%to_orb(:connection_ki%nexcit)

!           connection%to_orb(connection_ki%nexcit+1:connection%nexcit) = &
!                               connection_jk%to_orb(:connection_jk%nexcit)
            
            

        else if (choose_double_elt_type <= P__ + P_o ) then elttype
            !          _
            !         / \
            !    .____\./
            !    i    k,j
            

            ! 1.1 Generate first random excitation and probability of spawning there from cdet 
            call gen_excit_ptr(cdet, Pgen_ki, connection_ki, hmatel_ki)


            ! 1.2 Generate the second random excitation 
            !    (in this case we stay on the same place)
            ! (i)  generate the first excited determinant  
            call create_excited_det_complete(cdet, connection_ki, cdet_excit) !could optimise this with create_excited det - we only need %f
            ! (ii) calculate Pgen and hmatel on this site       
            Pgen_jk = 1
            hmatel_jk =  sc0_ptr(cdet_excit%f) - H00 - fold_line !***optimise this with stored/calculated values
            
            ! 2. Probability of gening...
            pgen = P_o * Pgen_ki * Pgen_jk
            pspawn = tau*abs(hmatel_ki*hmatel_jk)/pgen
            
            ! 3. Attempt spawning.
            psuccess = rng_ptr()

            ! Need to take into account the possibilty of a spawning attempt
            ! producing multiple offspring...
            ! If pspawn is > 1, then we spawn floor(pspawn) as a minimum and 
            ! then spawn a particle with probability pspawn-floor(pspawn).
            nspawn = int(pspawn)
            pspawn = pspawn - nspawn

            if (pspawn > psuccess) nspawn = nspawn + 1

            if (nspawn > 0) then

                ! 4. If H_ij is positive, then the spawned walker is of opposite
                ! sign to the parent, otherwise the spawned walkers if of the same
                ! sign as the parent.
                if (hmatel_ki*hmatel_jk > 0.0_p) then
                    nspawn = -sign(nspawn, parent_sign)
                else
                    nspawn = sign(nspawn, parent_sign)
                end if

            end if

            ! 5. Set connection to the address of the spawned element
            connection = connection_ki


        else elttype

            !     _
            !    / \
            !    \./____.
            !    i,k    j


            ! 1.1 Generate first random excitation and probability of spawning there from cdet 
            !    (in this case we stay on the same place)
            Pgen_ki = 1
            hmatel_ki =  sc0_ptr(cdet%f) - H00 - fold_line !***optimise this with stored/calculated values
            

            ! 1.2 Generate the second random excitation 
            call gen_excit_ptr(cdet, Pgen_jk, connection_jk, hmatel_jk)
            
            ! 2. Probability of gening...
            pgen = Po_ * Pgen_ki * Pgen_jk
            pspawn = tau*abs(hmatel_ki*hmatel_jk)/pgen
            
            ! 3. Attempt spawning.
            psuccess = rng_ptr()

            ! Need to take into account the possibilty of a spawning attempt
            ! producing multiple offspring...
            ! If pspawn is > 1, then we spawn floor(pspawn) as a minimum and 
            ! then spawn a particle with probability pspawn-floor(pspawn).
            nspawn = int(pspawn)
            pspawn = pspawn - nspawn

            if (pspawn > psuccess) nspawn = nspawn + 1

            if (nspawn > 0) then

                ! 4. If H_ij is positive, then the spawned walker is of opposite
                ! sign to the parent, otherwise the spawned walkers if of the same
                ! sign as the parent.
                if (hmatel_ki*hmatel_jk > 0.0_p) then
                    nspawn = -sign(nspawn, parent_sign)
                else
                    nspawn = sign(nspawn, parent_sign)
                end if

            end if

            ! 5. Set connection to the address of the spawned element
            connection = connection_jk


        endif elttype



    end subroutine fs_spawner










    subroutine fs_stochastic_death(Kii, population, tot_population, ndeath)

        ! Particles will attempt to die with probability
        !  p_d = tau*M_ii
        ! where tau is the timestep and M_ii is the appropriate diagonal
        ! matrix element.
        ! For FSFCIQMC M_ii = (K_ii-fold_line)^2 + fs_offset - S        
        ! where S is the shift, fold_line is the point about which we fold
        ! the spectrum, fs_offset is an addition offset to move the origin 
        ! from zero and  K_ii is
        !  K_ii =  < D_i | H | D_i > - E_0.

        ! In:
        !    Kii: < D_i | H | D_i > - E_0, where D_i is the determinant on
        !         which the particles reside.
        ! In/Out:
        !    population: number of particles on determinant D_i.
        !    tot_population: total number of particles.
        ! Out:
        !    ndeath: running total of number of particles died/cloned.
        
        ! Note that population and tot_population refer to a single 'type' of
        ! population, i.e. either a set of Hamiltonian walkers or a set of
        ! Hellmann--Feynman walkers.
        !      ___
        !     / _ \
        !    | / \ |
        !     \\.//



        use death, only: stochastic_death

        real(p), intent(in) :: Kii
        integer, intent(inout) :: population, tot_population
        integer, intent(out) :: ndeath

        call stochastic_death((Kii-fold_line)**2+fs_offset, population, tot_population, ndeath)

    end subroutine fs_stochastic_death


end module folded_spectrum_utils


