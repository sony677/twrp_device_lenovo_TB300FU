# Stock prebuilts

Add these two files from the exact `TB300FU_S101116_251224_ROW` stock `boot.img`:

| Repository path | Expected size | Local source |
| --- | ---: | --- |
| `prebuilt/kernel` | 11,824,113 bytes | `extraido_dispositivo\prebuilt_kernel` |
| `prebuilt/dtb.img` | 120,386 bytes | `extraido_dispositivo\prebuilt_dtb` |

They were extracted with MagiskBoot 30.6 using the no-decompression option:

```sh
magiskboot unpack -n boot.img
```

Do not substitute files from another firmware revision. The workflow checks both sizes before syncing Android sources.
