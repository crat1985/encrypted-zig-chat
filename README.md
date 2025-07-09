# Encrypted Zig Chat
This chat is E2EE.

# TODO
- [ ] Protocol
    - [x] Authentication (using Ed25519 signatures)
    - [x] E2EE (using X25519 key exchange)
    - [x] Send messages to an user using their ID (= X25519 public key)
    - [x] Send files
    - [x] Force any user to wait for authrization from the other part to send a message/file (except if the message is from us and to another user, it is however still the case for a me to me conversation)
    - [ ] Perhaps add the actual sender in the encrypted part, to prevent an evil server from exchanging the sender and the receiver of a message ?
- [ ] GUI
    - [x] Connect to the server
    - [x] Authenticate using a passphrase (which will be derived)
    - [x] Send messages
    - [x] Send files
    - [ ] Ask the user for confirmation to accept the message if the message is either from a new sender or too large (e.g. 10ko)
    - [ ] Show message requests and their avancement the same way as messages
    - [x] Put each file in their DM directory
    - [x] E2EE the files
    - [ ] Patch Windows lags and "Not responding" issues
    - [ ] Perhaps display small images directly in the app ?
    - [ ] Perhaps even display small videos/gifs directly in the app ?
    - [ ] Speed up file transfers by using "seek" and more multi-threading ?
- [ ] E2EE files decrypt script
    - [x] Basic file decryption
    - [x] Put the decrypted files in the TMP directory
    - [ ] Delete the files after some time (e.g. 10 minutes) ?