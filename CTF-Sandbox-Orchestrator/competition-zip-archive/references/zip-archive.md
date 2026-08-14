# ZIP Archive Challenge Reference

## Route Decision

| Observation | Next step |
|---|---|
| ZIP/PKZIP archive, legacy encryption, predictable member bytes | Use `bkcrack` known-plaintext recovery |
| Entry is stored and its file format is known | Build a matching plaintext fixture and attack the entry |
| Entry is deflated | Match the compressed entry bytes; do not pass an unrelated uncompressed file |
| WinZip AES or another modern encryption mode | `bkcrack` is not the right primitive; re-route |
| Upload reaches an application parser or extractor | Use `competition-file-parser-chain` |
| Archive is only a carrier for hidden media data | Use `competition-stego-media` |

## Minimal Inspection

```text
file challenge.zip
bkcrack -L challenge.zip
7z l -slt challenge.zip
```

Record the entry name, compression method, encrypted flag, compressed size, uncompressed size, CRC, and any duplicate entries. The ZIP local-file and central-directory signatures are archive metadata; seeing `PK` in the container does not disclose the plaintext of an encrypted member.

## Known-Plaintext Requirements

Legacy ZipCrypto key recovery needs at least 12 known plaintext bytes. At least 8 bytes should be contiguous; more contiguous bytes improve speed and reliability. Good sources include:

- a challenge-provided template or source file;
- a predictable file signature plus enough fixed header bytes;
- a known serialized structure with stable fields;
- a second entry encrypted with the same password and a known exact representation.

For compressed entries, the bytes must correspond to the encrypted data representation. A plaintext ZIP fixture is useful because `bkcrack -P`/`-p` lets the tool read the matching entry representation.

## Command Forms

Archive entry to archive entry:

```bash
bkcrack -C encrypted.zip -c cipher -P plain.zip -p plain
```

Raw files, with an offset or sparse bytes when justified by evidence:

```bash
bkcrack -c cipherfile -p plainfile -o offset
bkcrack -c cipherfile -p plainfile -x 25 4b4f -x 30 21
```

Decrypt every compatible entry after key recovery:

```bash
bkcrack -C encrypted.zip -k 12345678 23456789 34567890 -D unlocked.zip
```

Decrypt one raw member:

```bash
bkcrack -c cipherfile -k 12345678 23456789 34567890 -d decipheredfile
```

Do not publish a command with placeholder keys as if it were a successful solve. Replace them with the values from the actual recovery output and record the source evidence.

## Evidence Checklist

- [ ] Original archive hash recorded before any extraction
- [ ] Archive type and encryption mode confirmed
- [ ] Entry name and compression method recorded
- [ ] Known plaintext bytes and their source explained
- [ ] At least 12 known bytes, including 8 contiguous bytes, or justified sparse offsets
- [ ] Key recovery output saved
- [ ] Decrypted archive tested and extracted from a new path
- [ ] Final artifact or flag independently validated
