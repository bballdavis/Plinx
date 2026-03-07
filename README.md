# Plinx: Plink & Play 🚀

**Plinx** is a zero-friction, unbreakable media portal for children. Built for iOS 26 with a high-fidelity **Liquid Glass** UI, it transforms your Plex library into a safe, tactile, and playful discovery space.

---

## 🎨 Vision & Experience

- **Liquid Glass UI:** A physical, refractive interface with specular highlights and "squishy" animations.
- **Plink & Play:** Every interaction triggers the signature "Plink" sound effect paired with high-intensity haptic feedback.
- **Plinxie:** Our friendly mascot robot who guides children through loading states and keeps the "math gate" for parents.

## 🛡️ Safety & Security

- **Hard-coded Filtering:** Plinx automatically intercepts any media missing the "Kids" label or exceeding "TV-Y" / "G" ratings.
- **Parental Gate:** Access to settings is protected by a Plinxie-themed math challenge.
- **Physical Protection:** Immediate playback cessation and memory clearing on backgrounding; includes a **Baby Lock** triple-tap gesture to prevent accidental inputs.
- **Zero Collection:** We collect no data. Period. See `PrivacyInfo.xcprivacy` and the full text in `PRIVACY_POLICY.md`.

## ❤️ Credits & Foundations

Plinx is built upon the robust, open-source engine of **[Strimr](https://github.com/wunax/strimr)**. 

We owe a massive debt of gratitude to the Strimr contributors. Plinx uses Strimr's highly optimized backend and MPVKit integration to handle 4K, HDR, and MKV content with ease. Our architecture is designed to remain compatible with Strimr improvements, allowing us to focus on creating the best possible interface for children. **We are committed to the upstream project; any new features or engine enhancements we build that aren't specific to our branding are actively pushed back to the main Strimr repository.**

## 🛠️ Repository Architecture

- `Packages/PlinxCore`: Business logic, Safety Interceptor, and Haptic/Audio managers.
- `Packages/PlinxUI`: Liquid Glass design system and mascot assets.
- `PlinxApp`: The composition root and main app target.
- `Vendor/Strimr`: The upstream Strimr submodule for core media handling.

## 🚀 Getting Started

1. **Clone with submodules:**
   ```bash
   git clone --recursive https://github.com/bballdavis/Plinx.git
   ```
2. **Generate Project:**
   Plinx uses **XcodeGen**. Install it via Homebrew (`brew install xcodegen`) then run:
   ```bash
   cd PlinxApp && xcodegen generate
   ```
3. **Contribute:**
   See [development/UPSTREAM_SYNC.md](development/UPSTREAM_SYNC.md) for details on our mirror flow and contribution guidelines.

---

## ⚖️ License

Plinx is licensed under the same terms as Strimr (GPL-3.0). See [LICENSE](LICENSE) for details.
