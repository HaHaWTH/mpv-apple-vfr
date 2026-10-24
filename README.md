# mpv-apple-vfr

Automatically reduce the brightness and contrast of flashing video using Apple's **Video Flashing Reduction** algorithm.

## Installation

Copy these three directories into your mpv configuration directory:

```text
portable_config/
├── scripts/apple-vfr.lua
├── shaders/apple-vfr.glsl
└── script-opts/apple-vfr.conf
```

## Controls

| Key | Action |
| --- | --- |
| `Ctrl+Alt+f` | Toggle processing |
| `Ctrl+Alt+c` | Compare the original left half with the processed right half |
| `Ctrl+Alt+i` | Display the current model settings |

## Configuration

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `yes` | Enable processing |
| `peak_nits` | `500` | Model parameter U: luminance assigned to normalized linear white |
| `area_deg2` | `1265.63` | Model parameter A: viewing area in square degrees |
| `fps` | `0` | Sample frame rate, values > 0 will override the auto mode |
| `comparison` | `no` | Enable the split comparison |

```
## Credits

- [Apple technical summary, v1.0](https://developer.apple.com/accessibility/downloads/Video-Flashing-Reduction-12.pdf)
- [Apple implementation](https://github.com/apple-aiml-research/VideoFlashingReduction/)
