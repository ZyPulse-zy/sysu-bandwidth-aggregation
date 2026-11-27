# SYSU Bandwidth Aggregation

[中文文档](README.md)

An OpenWrt / ImmortalWrt field guide for combining the capacity of several authorized Sun Yat-sen University campus network sessions. MiniEAP authenticates each MacVLAN separately on one Ethernet uplink. Connection-level policy routing distributes new IPv4 connections across healthy WANs. Each connection keeps one WAN and can use only that WAN's capacity.

The tested JDCloud Athena RE-CS-02 uses five WANs for ordinary traffic and reserves WAN6 for games. The router directory contains reference scripts with device-specific dependencies.

## Router reference

Start by verifying one authenticated WAN and read the dependencies for your target firmware. [Porting guide](docs/getting-started.md) · [Router files](reference/router/README.md)

The five-WAN Steam comparison recorded median physical WAN reception of 443.7 Mbps and Steam socket goodput of 404.5 Mbps. The gaming measurements use synthetic UDP probes. [Measurement conditions](evidence/README.md)

This is an independent project. Follow your campus network rules and use accounts you are authorized to use. [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
