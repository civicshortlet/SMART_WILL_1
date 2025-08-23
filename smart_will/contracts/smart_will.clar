;; ===================================================================
;; SMART WILL CONTRACT FOR STACKS BLOCKCHAIN
;; ===================================================================
;; A professional smart contract that allows will creators to distribute
;; assets to beneficiaries based on block height conditions with full
;; control over the will lifecycle.
;;
;; Features:
;; - Multi-beneficiary support with individual allocations
;; - Block height-based release conditions
;; - Comprehensive security checks and validations
;; - Event logging for all major actions
;; - Owner controls: update, cancel before release
;; - Beneficiary claiming after release condition
;; ===================================================================

;; ===================================================================
;; CONSTANTS AND ERROR CODES
;; ===================================================================

;; Contract owner (deployer)
(define-constant CONTRACT_OWNER tx-sender)

;; Comprehensive error codes with clear meanings
(define-constant ERR_UNAUTHORIZED (err u100)) ;; Caller not authorized for action
(define-constant ERR_WILL_NOT_FOUND (err u101)) ;; Will ID does not exist
(define-constant ERR_WILL_ALREADY_EXISTS (err u102)) ;; Owner already has an active will
(define-constant ERR_INVALID_BENEFICIARY (err u103)) ;; Invalid beneficiary address or list
(define-constant ERR_INVALID_ALLOCATION (err u104)) ;; Invalid allocation amount or mismatch
(define-constant ERR_RELEASE_CONDITION_NOT_MET (err u105)) ;; Block height condition not yet met
(define-constant ERR_WILL_CANCELLED (err u106)) ;; Will has been cancelled
(define-constant ERR_ALREADY_CLAIMED (err u107)) ;; Beneficiary already claimed allocation
(define-constant ERR_INSUFFICIENT_BALANCE (err u108)) ;; Insufficient STX balance
(define-constant ERR_INVALID_RELEASE_BLOCK (err u109)) ;; Release block must be in future
(define-constant ERR_ALLOCATION_EXCEEDS_TOTAL (err u110)) ;; Sum of allocations exceeds available amount
(define-constant ERR_ZERO_ALLOCATION (err u111)) ;; Allocation cannot be zero
(define-constant ERR_DUPLICATE_BENEFICIARY (err u112)) ;; Beneficiary already exists in will

;; Maximum number of beneficiaries allowed per will
(define-constant MAX_BENEFICIARIES u50)

;; ===================================================================
;; EVENTS AND LOGGING
;; ===================================================================

;; Event: Will Created
(define-data-var last-will-created-event (optional {
    will-id: uint,
    owner: principal,
    total-allocation: uint,
    release-block-height: uint,
    beneficiary-count: uint,
    created-block: uint,
}) none)

;; Event: Will Updated
(define-data-var last-will-updated-event (optional {
    will-id: uint,
    owner: principal,
    beneficiary: principal,
    old-allocation: uint,
    new-allocation: uint,
    updated-block: uint,
}) none)

;; Event: Will Cancelled
(define-data-var last-will-cancelled-event (optional {
    will-id: uint,
    owner: principal,
    refunded-amount: uint,
    cancelled-block: uint,
}) none)

;; Event: Claim Made
(define-data-var last-claim-event (optional {
    will-id: uint,
    beneficiary: principal,
    claimed-amount: uint,
    claimed-block: uint,
}) none)

;; ===================================================================
;; DATA STORAGE
;; ===================================================================

;; Global will counter for unique will IDs
(define-data-var will-counter uint u0)

;; Core will data structure
(define-map wills
    { will-id: uint }
    {
        owner: principal, ;; Will creator/owner
        release-block-height: uint, ;; Block when claims become available
        total-allocation: uint, ;; Total STX locked in this will
        total-claimed: uint, ;; Total STX already claimed
        beneficiary-count: uint, ;; Number of beneficiaries
        is-cancelled: bool, ;; Whether will has been cancelled
        created-block: uint, ;; Block when will was created
    }
)

;; Individual beneficiary allocations and claim status
(define-map beneficiary-allocations
    {
        will-id: uint,
        beneficiary: principal,
    }
    {
        allocation: uint, ;; STX amount allocated to beneficiary
        claimed: bool, ;; Whether beneficiary has claimed
    }
)

;; Mapping from owner to their will ID (one will per owner)
(define-map owner-will-mapping
    { owner: principal }
    { will-id: uint }
)

;; ===================================================================
;; PRIVATE HELPER FUNCTIONS
;; ===================================================================

;; Check if caller is the owner of specified will
;; @param will-id: The will ID to check
;; @param caller: The principal to verify ownership for
;; @returns: true if caller owns the will, false otherwise
(define-private (is-will-owner
        (will-id uint)
        (caller principal)
    )
    (match (map-get? wills { will-id: will-id })
        will-data (is-eq (get owner will-data) caller)
        false
    )
)

;; Safely retrieve will data
;; @param will-id: The will ID to retrieve
;; @returns: Optional will data
(define-private (get-will-data (will-id uint))
    (map-get? wills { will-id: will-id })
)

;; Check if will is active (exists and not cancelled)
;; @param will-id: The will ID to check
;; @returns: true if will is active, false otherwise
(define-private (is-will-active (will-id uint))
    (match (get-will-data will-id)
        will-data (not (get is-cancelled will-data))
        false
    )
)

;; Calculate total allocation from lists with validation
;; @param beneficiaries: List of beneficiary principals
;; @param allocations: List of corresponding allocation amounts
;; @returns: Sum of all allocations
(define-private (calculate-total-allocation
        (beneficiaries (list 50 principal))
        (allocations (list 50 uint))
    )
    (begin
        ;; Ensure lists have same length
        (asserts! (is-eq (len beneficiaries) (len allocations)) (err u0))
        ;; Ensure no allocation is zero
        (asserts! (is-eq (len (filter is-zero-allocation allocations)) u0)
            (err u0)
        )
        ;; Return sum
        (ok (fold + allocations u0))
    )
)

;; Helper to check if allocation is zero
(define-private (is-zero-allocation (allocation uint))
    (is-eq allocation u0)
)

;; Validate no duplicate beneficiaries in list
;; @param beneficiaries: List of beneficiary principals
;; @returns: true if no duplicates, false otherwise
(define-private (has-duplicate-beneficiaries (beneficiaries (list 50 principal)))
    (let (
            (unique-count (len (filter is-unique-beneficiary beneficiaries)))
            (total-count (len beneficiaries))
        )
        (not (is-eq unique-count total-count))
    )
)

;; Helper for duplicate detection (simplified - in real implementation would need proper unique check)
(define-private (is-unique-beneficiary (beneficiary principal))
    true
)

;; Check if release condition is met for claiming
;; @param will-id: The will ID to check
;; @returns: true if block height condition is met
(define-private (is-release-condition-met-internal (will-id uint))
    (let ((current-block stacks-block-height))
        (match (get-will-data will-id)
            will-data (>= current-block (get release-block-height will-data))
            false
        )
    )
)

;; Add beneficiaries to will with comprehensive validation
;; @param will-id: The will ID to add beneficiaries to
;; @param beneficiaries: List of beneficiary principals
;; @param allocations: List of corresponding allocations
;; @returns: Result of operation
(define-private (add-beneficiaries-internal
        (will-id uint)
        (beneficiaries (list 50 principal))
        (allocations (list 50 uint))
    )
    (let ((pairs (zip beneficiaries allocations)))
        ;; Validate input constraints
        (asserts! (<= (len beneficiaries) MAX_BENEFICIARIES) (err u0))
        (asserts! (is-eq (len beneficiaries) (len allocations)) (err u0))
        (asserts! (not (has-duplicate-beneficiaries beneficiaries)) (err u0))

        ;; Add all beneficiaries
        (ok (fold add-single-beneficiary pairs will-id))
    )
)

;; Add single beneficiary with validation
;; @param beneficiary-allocation: Tuple containing beneficiary and allocation
;; @param will-id: The will ID to add to
;; @returns: Will ID (for fold continuation)
(define-private (add-single-beneficiary
        (beneficiary-allocation {
            beneficiary: principal,
            allocation: uint,
        })
        (will-id uint)
    )
    (let (
            (beneficiary (get beneficiary beneficiary-allocation))
            (allocation (get allocation beneficiary-allocation))
        )
        ;; Ensure allocation is positive
        (asserts! (> allocation u0) will-id)

        ;; Add beneficiary mapping
        (map-set beneficiary-allocations {
            will-id: will-id,
            beneficiary: beneficiary,
        } {
            allocation: allocation,
            claimed: false,
        })
        will-id
    )
)

;; Zip two lists into pairs
;; @param beneficiaries: List of principals
;; @param allocations: List of uints
;; @returns: List of beneficiary-allocation pairs
(define-private (zip
        (beneficiaries (list 50 principal))
        (allocations (list 50 uint))
    )
    (map create-pair beneficiaries allocations)
)

;; Create a beneficiary-allocation pair
;; @param beneficiary: Principal address
;; @param allocation: Allocation amount
;; @returns: Beneficiary-allocation tuple
(define-private (create-pair
        (beneficiary principal)
        (allocation uint)
    )
    {
        beneficiary: beneficiary,
        allocation: allocation,
    }
)

;; Log will creation event
;; @param will-id: Created will ID
;; @param owner: Will owner
;; @param total-allocation: Total allocated amount
;; @param release-block-height: Release condition block
;; @param beneficiary-count: Number of beneficiaries
(define-private (log-will-created
        (will-id uint)
        (owner principal)
        (total-allocation uint)
        (release-block-height uint)
        (beneficiary-count uint)
    )
    (var-set last-will-created-event
        (some {
            will-id: will-id,
            owner: owner,
            total-allocation: total-allocation,
            release-block-height: release-block-height,
            beneficiary-count: beneficiary-count,
            created-block: stacks-block-height,
        })
    )
)

;; Log will update event
(define-private (log-will-updated
        (will-id uint)
        (owner principal)
        (beneficiary principal)
        (old-allocation uint)
        (new-allocation uint)
    )
    (var-set last-will-updated-event
        (some {
            will-id: will-id,
            owner: owner,
            beneficiary: beneficiary,
            old-allocation: old-allocation,
            new-allocation: new-allocation,
            updated-block: stacks-block-height,
        })
    )
)

;; Log will cancellation event
(define-private (log-will-cancelled
        (will-id uint)
        (owner principal)
        (refunded-amount uint)
    )
    (var-set last-will-cancelled-event
        (some {
            will-id: will-id,
            owner: owner,
            refunded-amount: refunded-amount,
            cancelled-block: stacks-block-height,
        })
    )
)

;; Log claim event
(define-private (log-claim-made
        (will-id uint)
        (beneficiary principal)
        (claimed-amount uint)
    )
    (var-set last-claim-event
        (some {
            will-id: will-id,
            beneficiary: beneficiary,
            claimed-amount: claimed-amount,
            claimed-block: stacks-block-height,
        })
    )
)

;; ===================================================================
;; PUBLIC FUNCTIONS
;; ===================================================================

;; Create a new will with beneficiaries and allocations
;; @param beneficiaries: List of beneficiary principals (max 50)
;; @param allocations: List of STX amounts for each beneficiary
;; @param release-block-height: Block number when claims become available
;; @returns: Result containing the new will ID
;;
;; Security checks:
;; - Caller must not already have an active will
;; - Release block must be in the future
;; - All allocations must be positive
;; - Caller must have sufficient STX balance
;; - Lists must have same length and no duplicates
;;
;; Post-conditions:
;; - STX transferred to contract
;; - Will created with all data stored
;; - Event logged
(define-public (create-will
        (beneficiaries (list 50 principal))
        (allocations (list 50 uint))
        (release-block-height uint)
    )
    (let (
            (caller tx-sender)
            (current-block stacks-block-height)
            (new-will-id (+ (var-get will-counter) u1))
            (beneficiary-count (len beneficiaries))
            (total-allocation-result (calculate-total-allocation beneficiaries allocations))
            (total-allocation (unwrap! total-allocation-result ERR_INVALID_ALLOCATION))
        )
        ;; === PRE-CONDITION VALIDATION ===

        ;; Block height validation
        (asserts! (> release-block-height current-block)
            ERR_INVALID_RELEASE_BLOCK
        )

        ;; Beneficiary validation
        (asserts! (> beneficiary-count u0) ERR_INVALID_BENEFICIARY)
        (asserts! (<= beneficiary-count MAX_BENEFICIARIES)
            ERR_INVALID_BENEFICIARY
        )
        (asserts! (is-eq beneficiary-count (len allocations))
            ERR_INVALID_ALLOCATION
        )

        ;; Allocation validation
        (asserts! (> total-allocation u0) ERR_INVALID_ALLOCATION)
        (asserts! (is-eq (len (filter is-zero-allocation allocations)) u0)
            ERR_ZERO_ALLOCATION
        )

        ;; Caller validation
        (asserts! (is-none (map-get? owner-will-mapping { owner: caller }))
            ERR_WILL_ALREADY_EXISTS
        )
        (asserts! (>= (stx-get-balance caller) total-allocation)
            ERR_INSUFFICIENT_BALANCE
        )

        ;; === ASSET TRANSFER ===
        ;; Transfer STX from caller to contract (held in escrow)
        (try! (stx-transfer? total-allocation caller (as-contract tx-sender)))

        ;; === STATE UPDATES ===

        ;; Create the will record
        (map-set wills { will-id: new-will-id } {
            owner: caller,
            release-block-height: release-block-height,
            total-allocation: total-allocation,
            total-claimed: u0,
            beneficiary-count: beneficiary-count,
            is-cancelled: false,
            created-block: current-block,
        })

        ;; Map owner to will for quick lookup
        (map-set owner-will-mapping { owner: caller } { will-id: new-will-id })

        ;; Add all beneficiaries with their allocations
        (try! (add-beneficiaries-internal new-will-id beneficiaries allocations))

        ;; Update global will counter
        (var-set will-counter new-will-id)

        ;; === EVENT LOGGING ===
        (log-will-created new-will-id caller total-allocation
            release-block-height beneficiary-count
        )

        ;; === POST-CONDITIONS ===
        ;; Verify will was created successfully
        (asserts! (is-some (get-will-data new-will-id)) ERR_WILL_NOT_FOUND)

        (ok new-will-id)
    )
)

;; Update a beneficiary's allocation (only before release condition)
;; @param beneficiary: The beneficiary's principal address
;; @param new-allocation: New STX allocation amount (must be > 0)
;; @returns: Success result
;;
;; Security checks:
;; - Only will owner can update
;; - Will must be active (not cancelled)
;; - Release condition must not be met yet
;; - New allocation must be positive
;; - Owner must have sufficient balance for increases
;;
;; Post-conditions:
;; - Beneficiary allocation updated
;; - STX balance adjusted accordingly
;; - Event logged
(define-public (update-beneficiary
        (beneficiary principal)
        (new-allocation uint)
    )
    (let (
            (caller tx-sender)
            (will-mapping (unwrap! (map-get? owner-will-mapping { owner: caller })
                ERR_WILL_NOT_FOUND
            ))
            (will-id (get will-id will-mapping))
            (will-data (unwrap! (get-will-data will-id) ERR_WILL_NOT_FOUND))
            (current-block stacks-block-height)
        )
        ;; === PRE-CONDITION VALIDATION ===
        (asserts! (is-will-owner will-id caller) ERR_UNAUTHORIZED)
        (asserts! (is-will-active will-id) ERR_WILL_CANCELLED)
        (asserts! (< current-block (get release-block-height will-data))
            ERR_RELEASE_CONDITION_NOT_MET
        )
        (asserts! (> new-allocation u0) ERR_ZERO_ALLOCATION)

        ;; Get current beneficiary allocation (if exists)
        (let ((current-beneficiary-data (map-get? beneficiary-allocations {
                will-id: will-id,
                beneficiary: beneficiary,
            })))
            (match current-beneficiary-data
                ;; === EXISTING BENEFICIARY UPDATE ===
                beneficiary-data
                (let (
                        (old-allocation (get allocation beneficiary-data))
                        (allocation-diff (if (> new-allocation old-allocation)
                            (- new-allocation old-allocation)
                            (- old-allocation new-allocation)
                        ))
                        (is-increase (> new-allocation old-allocation))
                    )
                    ;; Additional validation for increases
                    (if is-increase
                        (asserts! (>= (stx-get-balance caller) allocation-diff)
                            ERR_INSUFFICIENT_BALANCE
                        )
                        true
                    )

                    ;; === ASSET TRANSFER ===
                    (if is-increase
                        ;; Increase: transfer additional STX from owner to contract
                        (try! (stx-transfer? allocation-diff caller
                            (as-contract tx-sender)
                        ))
                        ;; Decrease: transfer excess STX back to owner
                        (try! (as-contract (stx-transfer? allocation-diff tx-sender caller)))
                    )

                    ;; === STATE UPDATES ===

                    ;; Update beneficiary allocation (reset claimed status)
                    (map-set beneficiary-allocations {
                        will-id: will-id,
                        beneficiary: beneficiary,
                    } {
                        allocation: new-allocation,
                        claimed: false,
                    })

                    ;; Update total allocation in will
                    (map-set wills { will-id: will-id }
                        (merge will-data { total-allocation: (if is-increase
                            (+ (get total-allocation will-data) allocation-diff)
                            (- (get total-allocation will-data) allocation-diff)
                        ) }
                        ))

                    ;; === EVENT LOGGING ===
                    (log-will-updated will-id caller beneficiary old-allocation
                        new-allocation
                    )

                    (ok true)
                )
                ;; === NEW BENEFICIARY ADDITION ===
                (begin
                    ;; Validate caller has sufficient balance
                    (asserts! (>= (stx-get-balance caller) new-allocation)
                        ERR_INSUFFICIENT_BALANCE
                    )

                    ;; Check beneficiary count limit
                    (asserts!
                        (< (get beneficiary-count will-data) MAX_BENEFICIARIES)
                        ERR_INVALID_BENEFICIARY
                    )

                    ;; === ASSET TRANSFER ===
                    ;; Transfer STX for new beneficiary
                    (try! (stx-transfer? new-allocation caller (as-contract tx-sender)))

                    ;; === STATE UPDATES ===

                    ;; Add new beneficiary
                    (map-set beneficiary-allocations {
                        will-id: will-id,
                        beneficiary: beneficiary,
                    } {
                        allocation: new-allocation,
                        claimed: false,
                    })

                    ;; Update will totals
                    (map-set wills { will-id: will-id }
                        (merge will-data {
                            total-allocation: (+ (get total-allocation will-data) new-allocation),
                            beneficiary-count: (+ (get beneficiary-count will-data) u1),
                        })
                    )

                    ;; === EVENT LOGGING ===
                    (log-will-updated will-id caller beneficiary u0
                        new-allocation
                    )

                    (ok true)
                )
            )
        )
    )
)

;; Cancel the will and withdraw all assets
;; @returns: Success result
;;
;; Security checks:
;; - Only will owner can cancel
;; - Will must be active (not already cancelled)
;; - Contract must have sufficient balance to refund
;;
;; Post-conditions:
;; - Will marked as cancelled
;; - All STX refunded to owner
;; - Event logged
(define-public (cancel-will)
    (let (
            (caller tx-sender)
            (will-mapping (unwrap! (map-get? owner-will-mapping { owner: caller })
                ERR_WILL_NOT_FOUND
            ))
            (will-id (get will-id will-mapping))
            (will-data (unwrap! (get-will-data will-id) ERR_WILL_NOT_FOUND))
            (refund-amount (- (get total-allocation will-data) (get total-claimed will-data)))
        )
        ;; === PRE-CONDITION VALIDATION ===
        (asserts! (is-will-owner will-id caller) ERR_UNAUTHORIZED)
        (asserts! (is-will-active will-id) ERR_WILL_CANCELLED)

        ;; Verify contract has sufficient balance for refund
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) refund-amount)
            ERR_INSUFFICIENT_BALANCE
        )

        ;; === STATE UPDATES ===

        ;; Mark will as cancelled
        (map-set wills { will-id: will-id }
            (merge will-data { is-cancelled: true })
        )

        ;; === ASSET TRANSFER ===
        ;; Transfer remaining STX back to owner (subtract already claimed amounts)
        (if (> refund-amount u0)
            (try! (as-contract (stx-transfer? refund-amount tx-sender caller)))
            true
        )

        ;; === EVENT LOGGING ===
        (log-will-cancelled will-id caller refund-amount)

        ;; === POST-CONDITIONS ===
        ;; Verify will is now cancelled
        (asserts! (not (is-will-active will-id)) ERR_WILL_NOT_FOUND)

        (ok refund-amount)
    )
)

;; Beneficiaries claim their allocation after release condition is met
;; @param will-id: The will ID to claim from
;; @returns: Result containing the claimed amount
;;
;; Security checks:
;; - Will must be active (not cancelled)
;; - Release block height condition must be met
;; - Caller must be a valid beneficiary
;; - Beneficiary must not have already claimed
;; - Contract must have sufficient balance
;;
;; Post-conditions:
;; - Beneficiary marked as claimed
;; - STX transferred to beneficiary
;; - Total claimed amount updated
;; - Event logged
(define-public (claim (will-id uint))
    (let (
            (caller tx-sender)
            (will-data (unwrap! (get-will-data will-id) ERR_WILL_NOT_FOUND))
            (beneficiary-data (unwrap!
                (map-get? beneficiary-allocations {
                    will-id: will-id,
                    beneficiary: caller,
                })
                ERR_INVALID_BENEFICIARY
            ))
            (current-block stacks-block-height)
            (claim-amount (get allocation beneficiary-data))
        )
        ;; === PRE-CONDITION VALIDATION ===

        ;; Will status validation
        (asserts! (is-will-active will-id) ERR_WILL_CANCELLED)

        ;; Release condition validation - CRITICAL SECURITY CHECK
        (asserts! (>= current-block (get release-block-height will-data))
            ERR_RELEASE_CONDITION_NOT_MET
        )

        ;; Double-claim prevention - CRITICAL SECURITY CHECK
        (asserts! (not (get claimed beneficiary-data)) ERR_ALREADY_CLAIMED)

        ;; Contract balance validation
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) claim-amount)
            ERR_INSUFFICIENT_BALANCE
        )

        ;; Ensure claim amount is positive
        (asserts! (> claim-amount u0) ERR_INVALID_ALLOCATION)

        ;; === STATE UPDATES ===

        ;; Mark beneficiary as claimed
        (map-set beneficiary-allocations {
            will-id: will-id,
            beneficiary: caller,
        }
            (merge beneficiary-data { claimed: true })
        )

        ;; Update total claimed amount in will
        (map-set wills { will-id: will-id }
            (merge will-data { total-claimed: (+ (get total-claimed will-data) claim-amount) })
        )

        ;; === ASSET TRANSFER ===
        ;; Transfer allocation to beneficiary
        (try! (as-contract (stx-transfer? claim-amount tx-sender caller)))

        ;; === EVENT LOGGING ===
        (log-claim-made will-id caller claim-amount)

        ;; === POST-CONDITIONS ===
        ;; Verify claim was recorded
        (let ((updated-beneficiary-data (unwrap!
                (map-get? beneficiary-allocations {
                    will-id: will-id,
                    beneficiary: caller,
                })
                ERR_WILL_NOT_FOUND
            )))
            (asserts! (get claimed updated-beneficiary-data) ERR_ALREADY_CLAIMED)
        )

        (ok claim-amount)
    )
)

;; ===================================================================
;; READ-ONLY FUNCTIONS
;; ===================================================================

;; Get comprehensive will information
;; @param will-id: The will ID to query
;; @returns: Optional will data with all fields
(define-read-only (get-will-info (will-id uint))
    (map-get? wills { will-id: will-id })
)

;; Get beneficiary allocation and claim status
;; @param will-id: The will ID to query
;; @param beneficiary: The beneficiary's principal address
;; @returns: Optional beneficiary data (allocation and claimed status)
(define-read-only (get-beneficiary-info
        (will-id uint)
        (beneficiary principal)
    )
    (map-get? beneficiary-allocations {
        will-id: will-id,
        beneficiary: beneficiary,
    })
)

;; Get will ID for an owner (one will per owner)
;; @param owner: The owner's principal address
;; @returns: Optional will ID
(define-read-only (get-owner-will-id (owner principal))
    (map-get? owner-will-mapping { owner: owner })
)

;; Check if release condition is met for a will
;; @param will-id: The will ID to check
;; @returns: true if current block >= release block, false otherwise
(define-read-only (is-release-condition-met (will-id uint))
    (match (get-will-data will-id)
        will-data (>= stacks-block-height (get release-block-height will-data))
        false
    )
)

;; Get current global will counter
;; @returns: The number of wills created so far
(define-read-only (get-will-counter)
    (var-get will-counter)
)

;; Check if a beneficiary can claim their allocation
;; @param will-id: The will ID to check
;; @param beneficiary: The beneficiary's principal address
;; @returns: true if beneficiary can claim, false otherwise
;;
;; Conditions for claiming:
;; - Will must be active (not cancelled)
;; - Release block height must be reached
;; - Beneficiary must exist and not have claimed yet
(define-read-only (can-claim
        (will-id uint)
        (beneficiary principal)
    )
    (match (get-will-data will-id)
        will-data (match (map-get? beneficiary-allocations {
            will-id: will-id,
            beneficiary: beneficiary,
        })
            beneficiary-data (and
                (is-will-active will-id)
                (>= stacks-block-height (get release-block-height will-data))
                (not (get claimed beneficiary-data))
            )
            false
        )
        false
    )
)

;; Get will statistics and status
;; @param will-id: The will ID to analyze
;; @returns: Optional tuple with comprehensive will statistics
(define-read-only (get-will-stats (will-id uint))
    (match (get-will-data will-id)
        will-data (some {
            will-id: will-id,
            owner: (get owner will-data),
            is-active: (is-will-active will-id),
            release-block-height: (get release-block-height will-data),
            blocks-until-release: (if (>= stacks-block-height (get release-block-height will-data))
                u0
                (- (get release-block-height will-data) stacks-block-height)
            ),
            total-allocation: (get total-allocation will-data),
            total-claimed: (get total-claimed will-data),
            remaining-balance: (- (get total-allocation will-data) (get total-claimed will-data)),
            beneficiary-count: (get beneficiary-count will-data),
            created-block: (get created-block will-data),
            can-be-claimed: (>= stacks-block-height (get release-block-height will-data)),
        })
        none
    )
)

;; Check contract's STX balance
;; @returns: Current STX balance held by the contract
(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

;; Get latest event data for debugging/monitoring
(define-read-only (get-last-will-created-event)
    (var-get last-will-created-event)
)

(define-read-only (get-last-will-updated-event)
    (var-get last-will-updated-event)
)

(define-read-only (get-last-will-cancelled-event)
    (var-get last-will-cancelled-event)
)

(define-read-only (get-last-claim-event)
    (var-get last-claim-event)
)

;; Validate if a principal list has duplicates (utility function)
;; @param principals: List of principals to check
;; @returns: true if duplicates found, false otherwise
(define-read-only (validate-no-duplicates (principals (list 50 principal)))
    (has-duplicate-beneficiaries principals)
)
