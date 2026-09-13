# Third-party notices

The MIT license applies to original documentation, configuration compiler, offline editor and original maintenance script excerpts in this repository. It does not relicense upstream software.

## ath11k source patch

`patches/ath11k-cn-bandwidth-fix.patch` is a narrowly scoped proposed change to ath11k and contains context from `drivers/net/wireless/ath/ath11k/reg.c`. That source carries `SPDX-License-Identifier: BSD-3-Clause-Clear` and the following notices:

> Copyright (c) 2018-2019 The Linux Foundation. All rights reserved.
> Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.

The patch contribution is provided under BSD-3-Clause-Clear as well. See [license text](LICENSES/BSD-3-Clause-Clear.txt) and [patch status](docs/02-qcn9074-cn.md).

## Referenced but not bundled

- MiniEAP and SYSU adaptations: consult the selected upstream repository and revision license.
- cake-autorate: GPL-2.0; this package includes an original local parameter file, not the upstream implementation.
- sing-box, Mihomo/Xray and their respective licenses: only example configuration fields are included.
- MetaCubeX rule databases: URLs, fixed commit and hashes only; no SRS/JSON rule database is bundled. Downloading and redistribution remain subject to upstream licenses and notices.
- ImmortalWrt/OpenWrt, Linux, Qualcomm firmware, U-Boot and NSS: links and findings only; no firmware, module, calibration data or bootloader image is bundled.
- ACL4SSR, blackmatrix7 and SYSU guide authors: attributed as classification or historical references; their articles and complete configurations were not copied into this project.

The offline HTML editor is original project code. MetaCubeXD itself is not included in this public package.
