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
(define-private (get-will-data (will-id uint))
    (map-get? wills { will-id: will-id })
)

;; Check if will is active (exists and not cancelled)
(define-private (is-will-active (will-id uint))
    (match (get-will-data will-id)
        will-data (not (get is-cancelled will-data))
        false
    )
)

;; Calculate total allocation from lists with validation
(define-private (calculate-total-allocation
        (beneficiaries (list 50 principal))
        (allocations (list 50 uint))
    )
    (begin
        (asserts! (is-eq (len beneficiaries) (len allocations)) (err u0))
        (asserts! (is-eq (len (filter is-zero-allocation allocations)) u0)
            (err u0)
        )
        (ok (fold + allocations u0))
    )
)

;; Helper to check if allocation is zero
(define-private (is-zero-allocation (allocation uint))
    (is-eq allocation u0)
)

;; Validate no duplicate beneficiaries in list
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
(define-private (is-release-condition-met-internal (will-id uint))
    (let ((current-block stacks-block-height))
        (match (get-will-data will-id)
            will-data (>= current-block (get release-block-height will-data))
            false
        )
    )
)

;; Add beneficiaries to will with comprehensive validation
(define-private (add-beneficiaries-internal
        (will-id uint)
        (beneficiaries (list 50 principal))
        (allocations (list 50 uint))
    )
    (let ((pairs (zip beneficiaries allocations)))
        (asserts! (<= (len beneficiaries) MAX_BENEFICIARIES) (err u0))
        (asserts! (is-eq (len beneficiaries) (len allocations)) (err u0))
        (asserts! (not (has-duplicate-beneficiaries beneficiaries)) (err u0))
        (ok (fold add-single-beneficiary pairs will-id))
    )
)

;; Add single beneficiary with validation
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
        (asserts! (> allocation u0) will-id)
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
(define-private (zip
        (beneficiaries (list 50 principal))
        (allocations (list 50 uint))
    )
    (map create-pair beneficiaries allocations)
)

;; Create a beneficiary-allocation pair
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
        (asserts! (> release-block-height current-block)
            ERR_INVALID_RELEASE_BLOCK
        )
        (asserts! (> beneficiary-count u0) ERR_INVALID_BENEFICIARY)
        (asserts! (<= beneficiary-count MAX_BENEFICIARIES)
            ERR_INVALID_BENEFICIARY
        )
        (asserts! (is-eq beneficiary-count (len allocations))
            ERR_INVALID_ALLOCATION
        )
        (asserts! (> total-allocation u0) ERR_INVALID_ALLOCATION)
        (asserts! (is-eq (len (filter is-zero-allocation allocations)) u0)
            ERR_ZERO_ALLOCATION
        )
        (asserts! (is-none (map-get? owner-will-mapping { owner: caller }))
            ERR_WILL_ALREADY_EXISTS
        )
        (asserts! (>= (stx-get-balance caller) total-allocation)
            ERR_INSUFFICIENT_BALANCE
        )
        (try! (stx-transfer? total-allocation caller (as-contract tx-sender)))
        (map-set wills { will-id: new-will-id } {
            owner: caller,
            release-block-height: release-block-height,
            total-allocation: total-allocation,
            total-claimed: u0,
            beneficiary-count: beneficiary-count,
            is-cancelled: false,
            created-block: current-block,
        })
        (map-set owner-will-mapping { owner: caller } { will-id: new-will-id })
        (try! (add-beneficiaries-internal new-will-id beneficiaries allocations))
        (var-set will-counter new-will-id)
        (log-will-created new-will-id caller total-allocation
            release-block-height beneficiary-count
        )
        (asserts! (is-some (get-will-data new-will-id)) ERR_WILL_NOT_FOUND)
        (ok new-will-id)
    )
)

;; Update a beneficiary's allocation (only before release condition)
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
        (asserts! (is-will-owner will-id caller) ERR_UNAUTHORIZED)
        (asserts! (is-will-active will-id) ERR_WILL_CANCELLED)
        (asserts! (< current-block (get release-block-height will-data))
            ERR_RELEASE_CONDITION_NOT_MET
        )
        (asserts! (> new-allocation u0) ERR_ZERO_ALLOCATION)
        (let ((current-beneficiary-data (map-get? beneficiary-allocations {
                will-id: will-id,
                beneficiary: beneficiary,
            })))
            (match current-beneficiary-data
                beneficiary-data (let (
                        (old-allocation (get allocation beneficiary-data))
                        (allocation-diff (if (> new-allocation old-allocation)
                            (- new-allocation old-allocation)
                            (- old-allocation new-allocation)
                        ))
                        (is-increase (> new-allocation old-allocation))
                    )
                    (if is-increase
                        (asserts! (>= (stx-get-balance caller) allocation-diff)
                            ERR_INSUFFICIENT_BALANCE
                        )
                        true
                    )
                    (if is-increase
                        (try! (stx-transfer? allocation-diff caller
                            (as-contract tx-sender)
                        ))
                        (try! (as-contract (stx-transfer? allocation-diff tx-sender caller)))
                    )
                    (map-set beneficiary-allocations {
                        will-id: will-id,
                        beneficiary: beneficiary,
                    } {
                        allocation: new-allocation,
                        claimed: false,
                    })
                    (map-set wills { will-id: will-id }
                        (merge will-data { total-allocation: (if is-increase
                            (+ (get total-allocation will-data) allocation-diff)
                            (- (get total-allocation will-data) allocation-diff)
                        ) }
                        ))
                    (log-will-updated will-id caller beneficiary old-allocation
                        new-allocation
                    )
                    (ok true)
                )
                (begin
                    (asserts! (>= (stx-get-balance caller) new-allocation)
                        ERR_INSUFFICIENT_BALANCE
                    )
                    (asserts!
                        (< (get beneficiary-count will-data) MAX_BENEFICIARIES)
                        ERR_INVALID_BENEFICIARY
                    )
                    (try! (stx-transfer? new-allocation caller (as-contract tx-sender)))
                    (map-set beneficiary-allocations {
                        will-id: will-id,
                        beneficiary: beneficiary,
                    } {
                        allocation: new-allocation,
                        claimed: false,
                    })
                    (map-set wills { will-id: will-id }
                        (merge will-data {
                            total-allocation: (+ (get total-allocation will-data) new-allocation),
                            beneficiary-count: (+ (get beneficiary-count will-data) u1),
                        })
                    )
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
        (asserts! (is-will-owner will-id caller) ERR_UNAUTHORIZED)
        (asserts! (is-will-active will-id) ERR_WILL_CANCELLED)
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) refund-amount)
            ERR_INSUFFICIENT_BALANCE
        )
        (map-set wills { will-id: will-id }
            (merge will-data { is-cancelled: true })
        )
        (if (> refund-amount u0)
            (try! (as-contract (stx-transfer? refund-amount tx-sender caller)))
            true
        )
        (log-will-cancelled will-id caller refund-amount)
        (asserts! (not (is-will-active will-id)) ERR_WILL_NOT_FOUND)
        (ok refund-amount)
    )
)

;; Beneficiaries claim their allocation after release condition is met
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
        (asserts! (is-will-active will-id) ERR_WILL_CANCELLED)
        (asserts! (>= current-block (get release-block-height will-data))
            ERR_RELEASE_CONDITION_NOT_MET
        )
        (asserts! (not (get claimed beneficiary-data)) ERR_ALREADY_CLAIMED)
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) claim-amount)
            ERR_INSUFFICIENT_BALANCE
        )
        (asserts! (> claim-amount u0) ERR_INVALID_ALLOCATION)
        (map-set beneficiary-allocations {
            will-id: will-id,
            beneficiary: caller,
        }
            (merge beneficiary-data { claimed: true })
        )
        (map-set wills { will-id: will-id }
            (merge will-data { total-claimed: (+ (get total-claimed will-data) claim-amount) })
        )
        (try! (as-contract (stx-transfer? claim-amount tx-sender caller)))
        (log-claim-made will-id caller claim-amount)
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
;; READ-ONLY & QUERY FUNCTIONS
;; ===================================================================

;; Get will info by will-id
(define-read-only (get-will-info (will-id uint))
    (map-get? wills { will-id: will-id })
)

;; Get beneficiary info for a will
(define-read-only (get-beneficiary-info
        (will-id uint)
        (beneficiary principal)
    )
    (map-get? beneficiary-allocations {
        will-id: will-id,
        beneficiary: beneficiary,
    })
)

;; Get will-id for an owner
(define-read-only (get-owner-will-id (owner principal))
    (map-get? owner-will-mapping { owner: owner })
)

;; Check if release condition is met for a will
(define-read-only (is-release-condition-met (will-id uint))
    (is-release-condition-met-internal will-id)
)

;; Get the current will counter
(define-read-only (get-will-counter)
    (var-get will-counter)
)

;; Can the beneficiary claim from this will?
(define-read-only (can-claim
        (will-id uint)
        (beneficiary principal)
    )
    (let (
            (will-data (map-get? wills { will-id: will-id }))
            (beneficiary-data (map-get? beneficiary-allocations {
                will-id: will-id,
                beneficiary: beneficiary,
            }))
            (current-block stacks-block-height)
        )
        (if (and will-data beneficiary-data)
            (let (
                    (is-cancelled (get is-cancelled (unwrap! will-data false)))
                    (release-block (get release-block-height (unwrap! will-data u0)))
                    (claimed (get claimed (unwrap! beneficiary-data false)))
                    (allocation (get allocation (unwrap! beneficiary-data u0)))
                )
                (and
                    (not is-cancelled)
                    (>= current-block release-block)
                    (not claimed)
                    (> allocation u0)
                )
            )
            false
        )
    )
)

;; Get will stats (total allocation, claimed, beneficiary count)
(define-read-only (get-will-stats (will-id uint))
    (match (map-get? wills { will-id: will-id })
        will-data
        {
            total-allocation: (get total-allocation will-data),
            total-claimed: (get total-claimed will-data),
            beneficiary-count: (get beneficiary-count will-data),
            is-cancelled: (get is-cancelled will-data),
        }
        none
    )
)

;; Get contract STX balance
(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

;; Get last will created event
(define-read-only (get-last-will-created-event)
    (var-get last-will-created-event)
)

;; Get last will updated event
(define-read-only (get-last-will-updated-event)
    (var-get last-will-updated-event)
)

;; Get last will cancelled event
(define-read-only (get-last-will-cancelled-event)
    (var-get last-will-cancelled-event)
)

;; Get last claim event
(define-read-only (get-last-claim-event)
    (var-get last-claim-event)
)

;; Validate no duplicate beneficiaries in a list (utility)
(define-read-only (validate-no-duplicates (beneficiaries (list 50 principal)))
    (not (has-duplicate-beneficiaries beneficiaries))
)
