## Linux 0.11源码
使用qemu运行，主机使用的是macOS Catalina 10.15.1
运行前需要安装brew，然后安装模拟环境必备的编译软件和模拟器：
``` bash
brew install qemu i386-elf-binutils i386-elf-gcc
```
运行
```bash
make
qemu-system-i386  -boot a -fda Image -hda hdc-0.11.img
```