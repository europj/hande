module basis

! Basis function information.

use kpoints

implicit none

! Define a spin orbital.
type basis_fn
    ! Set of quantum numbers describing the basis function.
    ! l is used in two different contexts depending upon whether the orbitals
    ! are defined in momentum space or in real space.  Applies only to model
    ! Hamiltonians (e.g. Hubbard model).
    ! Momentum space:
    !     l is the wavevector in terms of the reciprocal lattice vectors of the crystal cell.
    ! Real space:
    !     l is the position of the basis function within the crystal cell in
    !     units of the lattice vectors of the primitive unit cell.
    ! Obviously we should not convert between descriptions within one
    ! calculation! ;-)
    integer, pointer :: l(:) => NULL()
    integer :: spatial_index
    ! Index of the irreducible representation spanned by the orbital.  Used only
    ! in systems where point group symmetry is used (e.g.  molecules).  See
    ! notes in pg_symmetry.
    integer :: sym = 0
    ! Index of basis function within the symmetry block.  sym_index = n
    ! indicates the basis function is the fifth in basis_fns array to have the
    ! symmetry given by sym.
    ! Used only with point_group symmetry.
    integer :: sym_index = 0
    ! Index of basis function within the symmetry block.  sym_spin_index = n
    ! indicates the basis function is the fifth in basis_fns array to have the
    ! symmetry given by sym *and* with the spin given by ms.
    ! Used only with point_group symmetry.
    integer :: sym_spin_index = 0
    ! Spin of the electron (1 or -1).
    integer :: ms
    ! single-particle energy of basis function.
    ! model Hamiltonians in momentum space:
    !     sp_eigv is the kinetic energy of the basis function.
    ! model Hamiltonians in real space:
    !     sp_eigv is not set/used.
    ! molecular systems:
    !     sp_eigv is the single-particle energy read in from the FCIDUMP file
    !     (e.g. Hartree--Fock or Kohn--Sham eigenvalue).
    real(p) :: sp_eigv 
end type basis_fn

! Store of information about the (spin) basis functions of the system.
! The *odd* indices contain the alpha (spin up) functions.  This is in
! contrast to the bit strings used to refer to determinants where the *even*
! bits refer to alpha (spin up) functions.  This difference arises because 
! fortran numbers bits from 0...
type(basis_fn), allocatable :: basis_fns(:) ! (nbasis)

! number of basis functions.
! For model Hamiltonians (e.g. Hubbard or Heisenberg) this is equal to 2*number
! of sites as there are 2 spin orbitals per site.
integer :: nbasis

! The determinants are stored as a bit string.  Each element of an array is
! an integer of kind i0 (containing i0_length bits).
! (The bit type has just been deleted from the forthcoming F2008 standard, so we
! won't hold our breath until we can use bits directly......)
! basis_length is the length of the byte array necessary to contain a bit for
! each basis function, i.e. ceiling(nbasis/i0_length).
! If separate_strings is true, then we actually store the alpha and beta
! strings separately, and so basis_length is 2*ceiling(nbasis/(2*i0_length)).
integer :: basis_length

! All bits in the determinant bit array correspond to a basis function apart
! from the last element in the bit array (which can contain some excess).
! last_basis_ind is the index of the last basis function in the last element of
! the bit array. 
integer :: last_basis_ind

! A determinant is stored in the array f(nbasis).  A basis function is occupied
! in the determinant if the relevant bit is set.  The relevant bit is given by
! bit_element, the element of the array which contains the bit corresponding to
! the basis function, and bit_position, which contains the position of the bit
! within the given element.  bit_lookup(:,i) gives the (/ bit_position,
! bit_element /) of the i-th basis function.
! Note fortran numbers bits starting from 0.
integer, allocatable :: bit_lookup(:,:) ! (2, nbasis)

! The reverse lookup to bit_lookup.
! basis_lookup(i,j) gives the basis function corresponding to
! the i-th bit in the j-th element of a determinant array.
integer, allocatable :: basis_lookup(:,:) ! (i0_length, basis_length)

contains

    subroutine init_basis_fn(b, l, sym, ms)

        ! Initialise a variable of type basis_fn.
        ! In:
        !    l (optional): quantum numbers of the basis function.  Used only in
        !        model Hamiltonians.
        !        Momentum space formulation:
        !            wavevector in units of the reciprocal lattice vectors of
        !            the crystal cell.
        !        Real space formulation:
        !            position of basis function within the crystal cell in units
        !            of the primitive lattice vectors.
        !    sym (optional): symmetry label of the basis function.  Used only in
        !        systems with point group symmetry (i.e. read in from an FCIDUMP
        !        file).
        !    ms (optional): set spin of an electron occupying the basis function.
        ! Out:
        !    b: initialsed basis function.  The wavevector and (if appropriate
        !      to the system) single-particle eigenvalue components are set if
        !      the l arguments is given and the ms component is set if the ms
        !      argument is given.  If no optional arguments are specified then
        !      a completely blank variable is returned.
        !
        ! This should be called even if l and ms are not specified so that the
        ! l component can be correctly allocated.

        use checking, only: check_allocate
        use system, only: system_type, hub_real

        type(basis_fn), intent(out) :: b
        integer, intent(in), optional  :: l(ndim)
        integer, intent(in), optional  :: sym, ms
        integer :: ierr

        if (.not.associated(b%l)) then
            allocate(b%l(ndim),stat=ierr)
            call check_allocate('b%l',ndim,ierr)
        end if

        if (present(l)) then
            b%l = l
            if (system_type == hub_k) then
                b%sp_eigv = calc_kinetic(l)
            else
                b%sp_eigv = 0.0_p
            end if
        end if

        if (present(sym)) b%sym = sym

        if (present(ms)) b%ms = ms

    end subroutine init_basis_fn

    subroutine write_basis_fn_header(iunit, print_full)

        ! Print out header for a table of basis functions.
        ! Format in line with write_basis_fn.
        !
        ! In:
        !    iunit (optional): io unit to which the output is written.
        !        Default: 6 (stdout).
        !    print_full (optional): if true (default) then print out header info
        !        for the symmetry and spin quantum numbers and (if appropriate)
        !        single-particle energy associated with the basis function.
        !        If false, only information about the quantum numbers is
        !        printed.

        use system, only: system_type, read_in, hub_k, hub_real

        integer, intent(in), optional :: iunit
        logical, intent(in), optional :: print_full

        integer :: io, i
        logical :: print_long

        if (present(iunit)) then
            io = iunit
        else
            io = 6
        end if

        ! If print_full is false, then the spin and single-particle eigenvalues
        ! are also printed out.
        if (present(print_full)) then
            print_long = print_full
        else
            print_long = .true.
        end if

        ! Title
        write (6,'(1X,a15,/,1X,15("-"),/)') 'Basis functions'

        ! Describe information.
        write (6,'(1X,a27)') 'Spin given in units of 1/2.'

        select case(system_type)
        case(hub_real)
            write (6,'(1X,a63,/)') 'Site positions given in terms of the primitive lattice vectors.'
            write (6,'(1X,a5,3X,a4,3X)', advance='no') 'index','site'
        case(hub_k)
            write (6,'(1X,a78)') 'k-points given in terms of the reciprocal lattice vectors of the crystal cell.'
            if (any(abs(ktwist) > 0.0_p)) then
                write (6,'(1X,a26)', advance='no') 'Applying a twist angle of:'
                write (6,'(1X,"(",f6.4)', advance='no') ktwist(1)
                do i = 2, ndim
                    write (6,'(",",f6.4)', advance='no') ktwist(i)
                end do
                write (6,'(").")')
            end if
            write (6,'()')
            write (6,'(1X,a5,3X,a7)', advance='no') 'index','k-point'
        case(read_in)
            write (6,'(/,1X,a5,2X,a7,X,a8,X,a9,2X)', advance='no') 'index','spatial','symmetry','sym_index'
        end select

        if (system_type /= read_in) then
            do i = 1, ndim
                write (6,'(4X)', advance='no')
            end do
        end if

        if (print_long) then
            write (6,'(a2)', advance='no') 'ms'

            if (system_type == hub_real) then
                write(6,'()')
            else
                write(6,'(5X,a7)') '<i|h|i>'
            end if
        else
            write (6,'()')
        end if

    end subroutine write_basis_fn_header

    subroutine write_basis_fn(b, ind, iunit, new_line, print_full)

        ! Print out information stored in b.
        ! Format in line with write_basis_fn_header.
        ! Please ensure formats are changed in both write_basis_fn and
        ! write_basis_fn_header.
        !
        ! In:
        !    b: basis_fn variable.
        !    ind: index of basis function.  Only printed out if present and
        !        positive.
        !    iunit (optional): io unit to which the output is written.
        !        Default: 6 (stdout).
        !    new_line (optional): if true, then a new line is written at
        !        the end of the list of occupied orbitals.  Default: no
        !        new line.
        !    print_full (optional): if true (default) then the symmetry and spin
        !        quantum numbers and (if appropriate) single-particle energy
        !        associated with the basis function are printed.  If false, only
        !        the quantum numbers are printed.

        use system, only: system_type, hub_real

        type(basis_fn), intent(in) :: b
        integer, intent(in), optional :: ind
        integer, intent(in), optional :: iunit
        logical, intent(in), optional :: new_line
        logical, intent(in), optional :: print_full
        logical :: print_all
        integer :: i, io

        if (present(iunit)) then
            io = iunit
        else
            io = 6
        end if

        if (present(print_full)) then
            print_all = print_full
        else
            print_all = .true.
        end if

        if (present(ind)) then
            if (ind >= 0) write (6,'(1X,i5,2X)',advance='no') ind
        end if

        if (system_type == read_in) then
            write (io, '(i5,2(3X,i5),X)',advance='no') b%spatial_index, b%sym, b%sym_index
        else
            write (io,'(1X,"(")', advance='no')
            write (io,'(i3)',advance='no') b%l(1)
            do i = 2,ndim
                write (io,'(",",i3)',advance='no') b%l(i)
            end do
            write (io,'(")")', advance='no')
        end if
        if (print_all) then
            write (io,'(5X,i2)', advance='no') b%ms
            if (system_type /= hub_real) write (io,'(4X,f12.8)', advance='no') b%sp_eigv
        end if
        if (present(new_line)) then
            if (new_line) write (io,'()')
        end if

    end subroutine write_basis_fn

    pure function spin_symmetry(i, j) result(spin_match)

        ! In:
        !    i: index of a basis function
        !    j: index of a basis function
        ! Returns:
        !    true if i and j refer to basis functions of the same spin.

        logical :: spin_match
        integer, intent(in) :: i, j

        spin_match = basis_fns(i)%ms == basis_fns(j)%ms

    end function spin_symmetry

    subroutine set_orb(f,iorb)

        ! In:
        !    f: bit string of orbitals.
        !    iorb: orbital index.
        ! Out:
        !    f: bit string of orbitals with the bit corresponding to iorb set. 
        
        ! Note that f must be zerod before first using this procedure.

        integer, intent(in) :: iorb
        integer(i0), intent(inout) :: f(basis_length)
        integer :: pos, ind

        pos = bit_lookup(1,iorb)
        ind = bit_lookup(2,iorb)
        f(ind) = ibset(f(ind),pos)

    end subroutine set_orb

    subroutine set_orb_mask(lmag2, orb_mask)

        ! Set a mask with bits set for symmetry-related orbitals.

        ! In:
        !    lmag2: magnitude squared of the l quantum vector (component of the
        !      basis_fn type) which corresponds to the desired set of
        !      symmetry-related orbitals.
        ! Out:
        !    orb_mask: bit-string where only bits are set that correspond to the
        !      set of symmetry-related orbitals with input value of lmag2.

        integer, intent(in) :: lmag2
        integer(i0), intent(out) :: orb_mask(basis_length)

        integer :: i, ipos, iel

        orb_mask = 0

        do i = 1, nbasis
            if (dot_product(basis_fns(i)%l,basis_fns(i)%l) == lmag2) then
                ipos = bit_lookup(1,i)
                iel = bit_lookup(2,i)
                orb_mask(iel) = ibset(orb_mask(iel), ipos)
            end if
        end do

    end subroutine set_orb_mask

    subroutine end_basis_fns()

        ! Clean up basis functions.

        use checking, only: check_deallocate

        integer :: ierr, i

        if (allocated(basis_fns)) then
            do i = 1, nbasis
                deallocate(basis_fns(i)%l, stat=ierr)
                call check_deallocate('basis_fns(i',ierr)
            end do
            deallocate(basis_fns, stat=ierr)
            call check_deallocate('basis_fns',ierr)
        end if

    end subroutine end_basis_fns

end module basis
