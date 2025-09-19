;; Optimize Graph: Goal Tracking and Verification System
;; A decentralized platform for personal goal management with advanced tracking and verification mechanisms

;; =======================================
;; Constants and Error Codes
;; =======================================
(define-constant system-admin tx-sender)

;; Error codes
(define-constant err-unauthorized (err u200))
(define-constant err-goal-not-found (err u201))
(define-constant err-milestone-not-found (err u202))
(define-constant err-goal-duplicate (err u203))
(define-constant err-milestone-duplicate (err u204))
(define-constant err-deadline-expired (err u205))
(define-constant err-goal-finalized (err u206))
(define-constant err-stake-insufficient (err u207))
(define-constant err-invalid-witness (err u208))
(define-constant err-privacy-invalid (err u209))
(define-constant err-invalid-deadline (err u210))
(define-constant err-milestone-completed (err u211))
(define-constant err-verification-pending (err u212))

;; Visibility settings
(define-constant visibility-open u1)
(define-constant visibility-restricted u2)

;; =======================================
;; Data Maps and Variables
;; =======================================

;; Maps goal unique identifier to goal details
(define-map goal-registry
  {
    creator: principal,
    goal-id: uint
  }
  {
    title: (string-ascii 100),
    description: (string-utf8 500),
    target-date: (optional uint),
    created-timestamp: uint,
    completion-timestamp: (optional uint),
    visibility: uint,
    verifier: (optional principal),
    stake-value: uint,
    total-checkpoints: uint,
    completed-checkpoints: uint
  }
)

;; Maps milestone details with goal tracking
(define-map milestone-tracking
  {
    creator: principal,
    goal-id: uint,
    milestone-id: uint
  }
  {
    title: (string-ascii 100),
    description: (string-utf8 500),
    is-complete: bool,
    completion-timestamp: (optional uint),
    verified-by: (optional principal)
  }
)

;; Tracks goal count per user
(define-map user-goal-counter principal uint)

;; =======================================
;; Private Helper Functions
;; =======================================

;; Retrieve next available goal ID for a user
(define-private (get-next-goal-identifier (user principal))
  (default-to u1 (map-get? user-goal-counter user))
)

;; Update goal counter for a user
(define-private (increment-user-goal-count (user principal))
  (let
    (
      (current-count (get-next-goal-identifier user))
    )
    (map-set user-goal-counter user (+ current-count u1))
    current-count
  )
)

;; Validate user's authorization for goal modification
(define-private (is-goal-creator (user principal) (goal-id uint))
  (is-eq tx-sender user)
)

;; Validate goal verifier status
(define-private (is-goal-verifier (user principal) (goal-id uint))
  (let
    (
      (goal-details (unwrap! (map-get? goal-registry {creator: user, goal-id: goal-id}) false))
      (verifier (get verifier goal-details))
    )
    (and
      (is-some verifier)
      (is-eq tx-sender (unwrap! verifier false))
    )
  )
)

;; Validate visibility configuration
(define-private (is-valid-visibility (visibility-mode uint))
  (or 
    (is-eq visibility-mode visibility-open)
    (is-eq visibility-mode visibility-restricted)
  )
)

;; =======================================
;; Public Read-Only Functions
;; =======================================

;; Retrieve goal details with access control
(define-read-only (get-goal-details (user principal) (goal-id uint))
  (let
    (
      (goal-data (map-get? goal-registry {creator: user, goal-id: goal-id}))
    )
    (if (is-some goal-data)
      (let
        (
          (unwrapped-goal (unwrap-panic goal-data))
          (goal-visibility (get visibility unwrapped-goal))
        )
        (if (or 
              (is-eq goal-visibility visibility-open)
              (is-eq tx-sender user)
              (is-eq tx-sender (default-to system-admin (get verifier unwrapped-goal)))
            )
          (ok unwrapped-goal)
          (err err-unauthorized)
        )
      )
      (err err-goal-not-found)
    )
  )
)

;; Retrieve milestone details with access control
(define-read-only (get-milestone-details (user principal) (goal-id uint) (milestone-id uint))
  (let
    (
      (goal-data (map-get? goal-registry {creator: user, goal-id: goal-id}))
    )
    (if (is-some goal-data)
      (let
        (
          (unwrapped-goal (unwrap-panic goal-data))
          (goal-visibility (get visibility unwrapped-goal))
          (milestone-data (map-get? milestone-tracking {creator: user, goal-id: goal-id, milestone-id: milestone-id}))
        )
        (if (and
              (is-some milestone-data)
              (or 
                (is-eq goal-visibility visibility-open)
                (is-eq tx-sender user)
                (is-eq tx-sender (default-to system-admin (get verifier unwrapped-goal)))
              )
            )
          (ok (unwrap-panic milestone-data))
          (err err-unauthorized)
        )
      )
      (err err-goal-not-found)
    )
  )
)

;; =======================================
;; Public Mutating Functions
;; =======================================

;; Create a new goal
(define-public (create-goal 
                (title (string-ascii 100))
                (description (string-utf8 500))
                (target-date (optional uint))
                (visibility uint)
                (verifier (optional principal))
                (stake-value uint))
  (let
    (
      (user tx-sender)
      (new-goal-id (increment-user-goal-count user))
    )
    ;; Validate inputs
    (asserts! (is-valid-visibility visibility) (err err-privacy-invalid))
    
    ;; Optional deadline validation
    (if (is-some target-date)
      (asserts! (> (unwrap-panic target-date) block-height) (err err-invalid-deadline))
      true
    )
    
    ;; Store goal details
    (map-set goal-registry
      {creator: user, goal-id: new-goal-id}
      {
        title: title,
        description: description,
        target-date: target-date,
        created-timestamp: block-height,
        completion-timestamp: none,
        visibility: visibility,
        verifier: verifier,
        stake-value: stake-value,
        total-checkpoints: u0,
        completed-checkpoints: u0
      }
    )
    
    (ok new-goal-id)
  )
)

;; Add a milestone to an existing goal
(define-public (add-milestone 
                (goal-id uint)
                (title (string-ascii 100))
                (description (string-utf8 500)))
  (let
    (
      (user tx-sender)
      (goal-data (unwrap! (map-get? goal-registry {creator: user, goal-id: goal-id}) (err err-goal-not-found)))
      (current-milestone-count (get total-checkpoints goal-data))
      (new-milestone-id (+ current-milestone-count u1))
    )
    ;; Validate goal creator
    (asserts! (is-goal-creator user goal-id) (err err-unauthorized))
    
    ;; Prevent milestone addition to completed goals
    (asserts! (is-none (get completion-timestamp goal-data)) (err err-goal-finalized))
    
    ;; Store milestone details
    (map-set milestone-tracking
      {creator: user, goal-id: goal-id, milestone-id: new-milestone-id}
      {
        title: title,
        description: description,
        is-complete: false,
        completion-timestamp: none,
        verified-by: none
      }
    )
    
    ;; Update goal's total checkpoints
    (map-set goal-registry
      {creator: user, goal-id: goal-id}
      (merge goal-data {total-checkpoints: new-milestone-id})
    )
    
    (ok new-milestone-id)
  )
)

;; Update goal's visibility settings
(define-public (modify-goal-visibility (goal-id uint) (new-visibility uint))
  (let
    (
      (user tx-sender)
      (goal-data (unwrap! (map-get? goal-registry {creator: user, goal-id: goal-id}) (err err-goal-not-found)))
    )
    ;; Validate authorization and new visibility
    (asserts! (is-goal-creator user goal-id) (err err-unauthorized))
    (asserts! (is-valid-visibility new-visibility) (err err-privacy-invalid))
    
    ;; Update visibility
    (map-set goal-registry
      {creator: user, goal-id: goal-id}
      (merge goal-data {visibility: new-visibility})
    )
    
    (ok true)
  )
)

;; Add or modify goal's verifier
(define-public (update-goal-verifier (goal-id uint) (new-verifier (optional principal)))
  (let
    (
      (user tx-sender)
      (goal-data (unwrap! (map-get? goal-registry {creator: user, goal-id: goal-id}) (err err-goal-not-found)))
    )
    ;; Validate authorization
    (asserts! (is-goal-creator user goal-id) (err err-unauthorized))
    
    ;; Prevent verifier changes after goal completion
    (asserts! (is-none (get completion-timestamp goal-data)) (err err-goal-finalized))
    
    ;; Update verifier
    (map-set goal-registry
      {creator: user, goal-id: goal-id}
      (merge goal-data {verifier: new-verifier})
    )
    
    (ok true)
  )
)