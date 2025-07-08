# Encrypted Zig Chat
This chat is E2EE.

# TODO
- [x] Protocol
    - [x] Authentication (using Ed25519 signatures)
    - [x] E2EE (using X25519 key exchange)
    - [x] Send messages to an user using their ID (= X25519 public key)
    - [x] Send files
    - [x] Force any user to wait for authrization from the other part to send a message/file (except if the message is from us and to another user, it is however still the case for a me to me conversation)
- [ ] GUI
    - [x] Connect to the server
    - [x] Authenticate using a passphrase (which will be derived)
    - [x] Send messages
    - [x] Send files
    - [ ] Ask the user for confirmation to accept the message if the message is either from a new sender or too large (e.g. 10ko)
    - [x] Put each file in their DM directory
    - [x] E2EE the files
    - [ ] Patch Windows lags and "Not responding" issues
- [x] E2EE files decrypt