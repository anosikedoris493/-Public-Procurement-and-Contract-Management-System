;; Contract Management System
;; Tracks contract execution and milestone management

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-CONTRACT-NOT-FOUND (err u301))
(define-constant ERR-MILESTONE-NOT-FOUND (err u302))
(define-constant ERR-INVALID-INPUT (err u303))
(define-constant ERR-MILESTONE-COMPLETED (err u304))

;; Data Variables
(define-data-var next-milestone-id uint u1)
(define-data-var total-milestones uint u0)

;; Data Maps
(define-map active-contracts
  { contract-id: uint }
  {
    contractor: principal,
    agency: principal,
    start-date: uint,
    end-date: uint,
    total-amount: uint,
    paid-amount: uint,
    status: (string-ascii 20),
    completion-percentage: uint
  }
)

(define-map contract-milestones
  { milestone-id: uint }
  {
    contract-id: uint,
    title: (string-ascii 200),
    description: (string-ascii 1000),
    due-date: uint,
    amount: uint,
    status: (string-ascii 20),
    completion-date: uint,
    deliverables: (string-ascii 2000),
    verification-notes: (string-ascii 1000)
  }
)

(define-map milestone-submissions
  { milestone-id: uint }
  {
    submitted-by: principal,
    submitted-at: uint,
    deliverable-hash: (string-ascii 64),
    submission-notes: (string-ascii 1000),
    status: (string-ascii 20)
  }
)

(define-map contract-performance
  { contract-id: uint }
  {
    on-time-milestones: uint,
    late-milestones: uint,
    quality-score: uint,
    contractor-rating: uint,
    last-updated: uint
  }
)

;; Contract Initialization
(define-public (initialize-contract
  (contract-id uint)
  (contractor principal)
  (agency principal)
  (start-date uint)
  (end-date uint)
  (total-amount uint)
)
  (begin
    (asserts! (> end-date start-date) ERR-INVALID-INPUT)
    (asserts! (> total-amount u0) ERR-INVALID-INPUT)

    (map-set active-contracts
      { contract-id: contract-id }
      {
        contractor: contractor,
        agency: agency,
        start-date: start-date,
        end-date: end-date,
        total-amount: total-amount,
        paid-amount: u0,
        status: "active",
        completion-percentage: u0
      }
    )

    (map-set contract-performance
      { contract-id: contract-id }
      {
        on-time-milestones: u0,
        late-milestones: u0,
        quality-score: u0,
        contractor-rating: u0,
        last-updated: block-height
      }
    )

    (ok true)
  )
)

;; Milestone Management
(define-public (create-milestone
  (contract-id uint)
  (title (string-ascii 200))
  (description (string-ascii 1000))
  (due-date uint)
  (amount uint)
  (deliverables (string-ascii 2000))
)
  (let
    (
      (milestone-id (var-get next-milestone-id))
      (contract-data (unwrap! (map-get? active-contracts { contract-id: contract-id })
        ERR-CONTRACT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get agency contract-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> due-date block-height) ERR-INVALID-INPUT)
    (asserts! (> amount u0) ERR-INVALID-INPUT)

    (map-set contract-milestones
      { milestone-id: milestone-id }
      {
        contract-id: contract-id,
        title: title,
        description: description,
        due-date: due-date,
        amount: amount,
        status: "pending",
        completion-date: u0,
        deliverables: deliverables,
        verification-notes: ""
      }
    )

    (var-set next-milestone-id (+ milestone-id u1))
    (var-set total-milestones (+ (var-get total-milestones) u1))

    (ok milestone-id)
  )
)

;; Milestone Submission
(define-public (submit-milestone
  (milestone-id uint)
  (deliverable-hash (string-ascii 64))
  (submission-notes (string-ascii 1000))
)
  (let
    (
      (milestone-data (unwrap! (map-get? contract-milestones { milestone-id: milestone-id })
        ERR-MILESTONE-NOT-FOUND))
      (contract-data (unwrap! (map-get? active-contracts { contract-id: (get contract-id milestone-data) })
        ERR-CONTRACT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get contractor contract-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status milestone-data) "pending") ERR-MILESTONE-COMPLETED)

    (map-set milestone-submissions
      { milestone-id: milestone-id }
      {
        submitted-by: tx-sender,
        submitted-at: block-height,
        deliverable-hash: deliverable-hash,
        submission-notes: submission-notes,
        status: "submitted"
      }
    )

    (map-set contract-milestones
      { milestone-id: milestone-id }
      (merge milestone-data { status: "submitted" })
    )

    (ok true)
  )
)

;; Milestone Verification
(define-public (verify-milestone
  (milestone-id uint)
  (approved bool)
  (verification-notes (string-ascii 1000))
  (quality-score uint)
)
  (let
    (
      (milestone-data (unwrap! (map-get? contract-milestones { milestone-id: milestone-id })
        ERR-MILESTONE-NOT-FOUND))
      (contract-data (unwrap! (map-get? active-contracts { contract-id: (get contract-id milestone-data) })
        ERR-CONTRACT-NOT-FOUND))
      (performance-data (unwrap! (map-get? contract-performance { contract-id: (get contract-id milestone-data) })
        ERR-CONTRACT-NOT-FOUND))
      (is-on-time (<= block-height (get due-date milestone-data)))
    )
    (asserts! (is-eq tx-sender (get agency contract-data)) ERR-NOT-AUTHORIZED)
    (asserts! (<= quality-score u100) ERR-INVALID-INPUT)

    (map-set contract-milestones
      { milestone-id: milestone-id }
      (merge milestone-data {
        status: (if approved "completed" "rejected"),
        completion-date: block-height,
        verification-notes: verification-notes
      })
    )

    ;; Update performance metrics
    (if approved
      (map-set contract-performance
        { contract-id: (get contract-id milestone-data) }
        (merge performance-data {
          on-time-milestones: (if is-on-time
            (+ (get on-time-milestones performance-data) u1)
            (get on-time-milestones performance-data)),
          late-milestones: (if is-on-time
            (get late-milestones performance-data)
            (+ (get late-milestones performance-data) u1)),
          quality-score: quality-score,
          last-updated: block-height
        })
      )
      true
    )

    (ok approved)
  )
)

;; Contract Status Updates
(define-public (update-contract-status (contract-id uint) (new-status (string-ascii 20)))
  (let
    (
      (contract-data (unwrap! (map-get? active-contracts { contract-id: contract-id })
        ERR-CONTRACT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get agency contract-data)) ERR-NOT-AUTHORIZED)

    (map-set active-contracts
      { contract-id: contract-id }
      (merge contract-data { status: new-status })
    )

    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-active-contract (contract-id uint))
  (map-get? active-contracts { contract-id: contract-id })
)

(define-read-only (get-milestone (milestone-id uint))
  (map-get? contract-milestones { milestone-id: milestone-id })
)

(define-read-only (get-milestone-submission (milestone-id uint))
  (map-get? milestone-submissions { milestone-id: milestone-id })
)

(define-read-only (get-contract-performance (contract-id uint))
  (map-get? contract-performance { contract-id: contract-id })
)

(define-read-only (get-total-milestones)
  (var-get total-milestones)
)

(define-read-only (calculate-completion-percentage (contract-id uint))
  ;; This would calculate based on completed milestones
  ;; Simplified implementation
  u0
)
