;; chain-mint
;; 
;; This contract manages the registration, tokenization, and trading of physical assets on the Stacks blockchain.
;; It provides a comprehensive framework for asset originators to register physical items, verifiers to authenticate them,
;; and users to trade fractional ownership of these tokenized assets while maintaining compliance with regulatory requirements.
;; The contract maintains complete lifecycle management from registration through verification, ownership transfers, and eventual retirement.

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ASSET-ALREADY-EXISTS (err u101))
(define-constant ERR-ASSET-NOT-FOUND (err u102))
(define-constant ERR-ASSET-NOT-VERIFIED (err u103))
(define-constant ERR-INSUFFICIENT-TOKENS (err u104))
(define-constant ERR-TRANSFER-FAILED (err u105))
(define-constant ERR-ASSET-ALREADY-TOKENIZED (err u106))
(define-constant ERR-INVALID-PARAMS (err u107))
(define-constant ERR-UNAUTHORIZED-VERIFIER (err u108))
(define-constant ERR-ASSET-RETIRED (err u109))
(define-constant ERR-COMPLIANCE-CHECK-FAILED (err u110))
(define-constant ERR-INVALID-TOKEN-AMOUNT (err u111))

;; Contract Owner
(define-constant CONTRACT-OWNER tx-sender)

;; Status Codes
(define-constant STATUS-PENDING u1)
(define-constant STATUS-VERIFIED u2)
(define-constant STATUS-REJECTED u3)
(define-constant STATUS-TOKENIZED u4)
(define-constant STATUS-RETIRED u5)

;; Data Structures

;; Stores information about physical assets
(define-map assets
  { asset-id: (string-ascii 36) }
  {
    owner: principal,
    status: uint,
    verifier: (optional principal),
    verification-date: (optional uint),
    metadata-url: (string-utf8 256),
    creation-date: uint,
    last-updated: uint,
    compliance-hash: (string-ascii 64),
    is-retired: bool
  }
)

;; Tracks tokenization details for each asset
(define-map asset-tokens
  { asset-id: (string-ascii 36) }
  {
    total-supply: uint,
    decimals: uint,
    token-uri: (string-utf8 256),
    tokenized-date: uint
  }
)

;; Tracks token balances for each asset and user
(define-map token-balances
  { asset-id: (string-ascii 36), owner: principal }
  { balance: uint }
)

;; List of authorized verifiers
(define-map authorized-verifiers
  { verifier: principal }
  { active: bool, added-at: uint }
)

;; Asset transfer history
(define-map asset-transfers
  { asset-id: (string-ascii 36), tx-id: uint }
  {
    from: principal,
    to: principal,
    amount: uint,
    timestamp: uint
  }
)

;; Global settings and counters
(define-data-var tx-counter uint u0)
(define-data-var verifier-count uint u0)
(define-data-var total-assets uint u0)

;; Private Functions

;; Helper function to check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Helper function to check if caller is an authorized verifier
(define-private (is-authorized-verifier)
  (default-to false (get active (map-get? authorized-verifiers { verifier: tx-sender })))
)

;; Helper function to check if an asset exists
(define-private (asset-exists (asset-id (string-ascii 36)))
  (is-some (map-get? assets { asset-id: asset-id }))
)

;; Helper function to check if caller is asset owner
(define-private (is-asset-owner (asset-id (string-ascii 36)))
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-some asset-data)
      (is-eq tx-sender (get owner (unwrap-panic asset-data)))
      false
    )
  )
)

;; Helper function to check asset tokenization state
(define-private (is-asset-tokenized (asset-id (string-ascii 36)))
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-some asset-data)
      (is-eq (get status (unwrap-panic asset-data)) STATUS-TOKENIZED)
      false
    )
  )
)

;; Helper function to check if asset is retired
(define-private (is-asset-retired (asset-id (string-ascii 36)))
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-some asset-data)
      (get is-retired (unwrap-panic asset-data))
      false
    )
  )
)

;; Helper function to get token balance
(define-private (get-token-balance (asset-id (string-ascii 36)) (owner principal))
  (default-to u0 
    (get balance (map-get? token-balances { asset-id: asset-id, owner: owner }))
  )
)

;; Helper to get next transaction ID
(define-private (get-next-tx-id)
  (let ((current-id (var-get tx-counter)))
    (var-set tx-counter (+ current-id u1))
    current-id
  )
)

;; Helper to perform compliance checks for transfers
(define-private (check-transfer-compliance (asset-id (string-ascii 36)) (sender principal) (recipient principal) (amount uint))
  ;; In a production environment, this would contain complex compliance logic
  ;; For this implementation, we'll do basic checks
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-some asset-data)
      (and 
        (not (get is-retired (unwrap-panic asset-data)))
        (is-eq (get status (unwrap-panic asset-data)) STATUS-TOKENIZED)
        (>= (get-token-balance asset-id sender) amount)
        (> amount u0)
      )
      false
    )
  )
)

;; Helper to update token balances during transfer
(define-private (update-balances (asset-id (string-ascii 36)) (sender principal) (recipient principal) (amount uint))
  (let (
    (sender-balance (get-token-balance asset-id sender))
    (recipient-balance (get-token-balance asset-id recipient))
  )
    ;; Update sender balance
    (map-set token-balances 
      { asset-id: asset-id, owner: sender }
      { balance: (- sender-balance amount) }
    )
    
    ;; Update recipient balance
    (map-set token-balances
      { asset-id: asset-id, owner: recipient }
      { balance: (+ recipient-balance amount) }
    )
    
    ;; Record the transfer in history
    (map-set asset-transfers
      { asset-id: asset-id, tx-id: (get-next-tx-id) }
      {
        from: sender,
        to: recipient,
        amount: amount,
        timestamp: block-height
      }
    )
    
    (ok true)
  )
)

;; Read-Only Functions

;; Check if a principal is an authorized verifier
(define-read-only (is-verifier (principal principal))
  (default-to false (get active (map-get? authorized-verifiers { verifier: principal })))
)

;; Get asset details
(define-read-only (get-asset (asset-id (string-ascii 36)))
  (if (asset-exists asset-id)
    (ok (map-get? assets { asset-id: asset-id }))
    ERR-ASSET-NOT-FOUND
  )
)

;; Get asset tokenization details
(define-read-only (get-asset-tokenization (asset-id (string-ascii 36)))
  (if (is-asset-tokenized asset-id)
    (ok (map-get? asset-tokens { asset-id: asset-id }))
    ERR-ASSET-NOT-VERIFIED
  )
)

;; Get token balance for a user
(define-read-only (get-balance (asset-id (string-ascii 36)) (owner principal))
  (ok { 
    asset-id: asset-id, 
    owner: owner, 
    balance: (get-token-balance asset-id owner) 
  })
)

;; Check if asset transfer would comply with regulations
(define-read-only (check-compliance (asset-id (string-ascii 36)) (sender principal) (recipient principal) (amount uint))
  (if (check-transfer-compliance asset-id sender recipient amount)
    (ok true)
    ERR-COMPLIANCE-CHECK-FAILED
  )
)

;; Public Functions

;; Register a new physical asset
(define-public (register-asset 
  (asset-id (string-ascii 36)) 
  (metadata-url (string-utf8 256))
  (compliance-hash (string-ascii 64))
)
  (let ((timestamp block-height))
    (if (asset-exists asset-id)
      ERR-ASSET-ALREADY-EXISTS
      (begin
        (map-set assets
          { asset-id: asset-id }
          {
            owner: tx-sender,
            status: STATUS-PENDING,
            verifier: none,
            verification-date: none,
            metadata-url: metadata-url,
            creation-date: timestamp,
            last-updated: timestamp,
            compliance-hash: compliance-hash,
            is-retired: false
          }
        )
        (var-set total-assets (+ (var-get total-assets) u1))
        (ok { asset-id: asset-id, status: STATUS-PENDING })
      )
    )
  )
)

;; Update asset metadata
(define-public (update-asset-metadata
  (asset-id (string-ascii 36))
  (metadata-url (string-utf8 256))
)
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-none asset-data)
      ERR-ASSET-NOT-FOUND
      (if (not (is-asset-owner asset-id))
        ERR-NOT-AUTHORIZED
        (if (is-asset-retired asset-id)
          ERR-ASSET-RETIRED
          (begin
            (map-set assets
              { asset-id: asset-id }
              (merge (unwrap-panic asset-data)
                {
                  metadata-url: metadata-url,
                  last-updated: block-height
                }
              )
            )
            (ok { asset-id: asset-id, updated: true })
          )
        )
      )
    )
  )
)

;; Add an authorized verifier
(define-public (add-verifier (verifier principal))
  (if (is-contract-owner)
    (begin
      (map-set authorized-verifiers
        { verifier: verifier }
        { active: true, added-at: block-height }
      )
      (var-set verifier-count (+ (var-get verifier-count) u1))
      (ok { verifier: verifier, added: true })
    )
    ERR-NOT-AUTHORIZED
  )
)

;; Remove a verifier
(define-public (remove-verifier (verifier principal))
  (if (is-contract-owner)
    (begin
      (map-set authorized-verifiers
        { verifier: verifier }
        { active: false, added-at: (default-to block-height (get added-at (map-get? authorized-verifiers { verifier: verifier }))) }
      )
      (var-set verifier-count (- (var-get verifier-count) u1))
      (ok { verifier: verifier, removed: true })
    )
    ERR-NOT-AUTHORIZED
  )
)

;; Verify an asset (only callable by authorized verifiers)
(define-public (verify-asset (asset-id (string-ascii 36)) (approve bool))
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-none asset-data)
      ERR-ASSET-NOT-FOUND
      (if (not (is-authorized-verifier))
        ERR-UNAUTHORIZED-VERIFIER
        (begin
          (map-set assets
            { asset-id: asset-id }
            (merge (unwrap-panic asset-data)
              {
                status: (if approve STATUS-VERIFIED STATUS-REJECTED),
                verifier: (some tx-sender),
                verification-date: (some block-height),
                last-updated: block-height
              }
            )
          )
          (ok { 
            asset-id: asset-id, 
            approved: approve, 
            status: (if approve STATUS-VERIFIED STATUS-REJECTED)
          })
        )
      )
    )
  )
)

;; Tokenize a verified asset
(define-public (tokenize-asset
  (asset-id (string-ascii 36))
  (total-supply uint)
  (decimals uint)
  (token-uri (string-utf8 256))
)
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-none asset-data)
      ERR-ASSET-NOT-FOUND
      (if (not (is-asset-owner asset-id))
        ERR-NOT-AUTHORIZED
        (if (not (is-eq (get status (unwrap-panic asset-data)) STATUS-VERIFIED))
          ERR-ASSET-NOT-VERIFIED
          (if (is-asset-tokenized asset-id)
            ERR-ASSET-ALREADY-TOKENIZED
            (begin
              ;; Update asset status to tokenized
              (map-set assets
                { asset-id: asset-id }
                (merge (unwrap-panic asset-data)
                  {
                    status: STATUS-TOKENIZED,
                    last-updated: block-height
                  }
                )
              )
              
              ;; Create token information
              (map-set asset-tokens
                { asset-id: asset-id }
                {
                  total-supply: total-supply,
                  decimals: decimals,
                  token-uri: token-uri,
                  tokenized-date: block-height
                }
              )
              
              ;; Assign all tokens to asset owner
              (map-set token-balances
                { asset-id: asset-id, owner: tx-sender }
                { balance: total-supply }
              )
              
              (ok { 
                asset-id: asset-id, 
                total-supply: total-supply,
                owner: tx-sender,
                status: STATUS-TOKENIZED
              })
            )
          )
        )
      )
    )
  )
)

;; Transfer tokens between users
(define-public (transfer-tokens
  (asset-id (string-ascii 36))
  (recipient principal)
  (amount uint)
)
  (let ((sender tx-sender))
    (if (not (asset-exists asset-id))
      ERR-ASSET-NOT-FOUND
      (if (not (is-asset-tokenized asset-id))
        ERR-ASSET-NOT-VERIFIED
        (if (is-asset-retired asset-id)
          ERR-ASSET-RETIRED
          (if (<= amount u0)
            ERR-INVALID-TOKEN-AMOUNT
            (if (> amount (get-token-balance asset-id sender))
              ERR-INSUFFICIENT-TOKENS
              (if (not (check-transfer-compliance asset-id sender recipient amount))
                ERR-COMPLIANCE-CHECK-FAILED
                (update-balances asset-id sender recipient amount)
              )
            )
          )
        )
      )
    )
  )
)

;; Retire an asset
(define-public (retire-asset (asset-id (string-ascii 36)))
  (let ((asset-data (map-get? assets { asset-id: asset-id })))
    (if (is-none asset-data)
      ERR-ASSET-NOT-FOUND
      (if (and (not (is-asset-owner asset-id)) (not (is-contract-owner)))
        ERR-NOT-AUTHORIZED
        (if (is-asset-retired asset-id)
          ERR-ASSET-RETIRED
          (begin
            (map-set assets
              { asset-id: asset-id }
              (merge (unwrap-panic asset-data)
                {
                  status: STATUS-RETIRED,
                  is-retired: true,
                  last-updated: block-height
                }
              )
            )
            (ok { asset-id: asset-id, retired: true })
          )
        )
      )
    )
  )
)