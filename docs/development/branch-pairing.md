# Branch Pairing

## Canonical Pairing

- Plinx `main` pairs with Strimr `plinx-patches`
- Plinx `dev` pairs with Strimr `dev-plinx`

Pinned development pairing:

- Plinx `dev`
- Strimr `dev-plinx` at
  `2eb041b2624d2f16fa93620c9b9a4b5b53c93c7d`

## Expected Local Layout

```text
Repos/
  Plinx/
  strimr/
```

Plinx runtime builds expect the sibling checkout at `../strimr`.

## Verification Commands

```bash
git -C <local path>/Repos/Plinx rev-parse --abbrev-ref HEAD
git -C <local path>/Repos/strimr rev-parse --abbrev-ref HEAD
```

## Before Starting Work

1. Verify Plinx and Strimr are on the intended paired branches.
2. Check `git status` in both repos.
3. Decide whether the change belongs in Plinx or Strimr before editing.
4. For `dev`, verify Strimr resolves to the commit recorded in
   `config/release-dependencies.env`; that revision descends from upstream
   `e0a8cbc` and adds only the documented compatibility seams.

## Rule Of Thumb

If the change is product-specific, work in Plinx. If the change is engine-specific or generally useful, work in Strimr.
