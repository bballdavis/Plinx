# Branch Pairing

## Canonical Pairing

- Plinx `main` pairs with Strimr `plinx-patches`
- Plinx `dev` pairs with Strimr `dev-plinx`

## Expected Local Layout

```text
Repos/
  Plinx/
  strimr/
  MPVKit/
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

## Rule Of Thumb

If the change is product-specific, work in Plinx. If the change is engine-specific or generally useful, work in Strimr.
