#include "asm.h"
#include "memlayout.h"
#include "mmu.h"

# ============================================
# 引导扇区代码 - 从实模式切换到保护模式
# 计算机加电后，BIOS将引导扇区加载到0x7C00
# 从这里开始执行16位实模式代码
# ============================================
# Start the first CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

.code16                       # Assemble for 16-bit mode
.globl start
start:
  cli                         # BIOS enabled interrupts; disable
# ---------------------------------------------------
  # 阶段1：实模式初始化
  # 清零段寄存器，确保从已知状态开始
  # ---------------------------------------------------
  # Zero data segment registers DS, ES, and SS.
  xorw    %ax,%ax             # Set %ax to zero
  movw    %ax,%ds             # -> Data Segment
  movw    %ax,%es             # -> Extra Segment
  movw    %ax,%ss             # -> Stack Segment
# ---------------------------------------------------
  # 阶段2：启用A20地址线
  # 这是为了突破8086的1MB内存限制
  # 通过键盘控制器端口0x64和0x60操作
  # ---------------------------------------------------
  # Physical address line A20 is tied to zero so that the first PCs 
  # with 2 MB would run software that assumed 1 MB.  Undo that.
seta20.1:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.1

  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64

seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.2

  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60

  # Switch from real to protected mode.  Use a bootstrap GDT that makes
  # virtual addresses map directly to physical addresses so that the
  # effective memory map doesn't change during the transition.
# ---------------------------------------------------
  # 阶段3：切换到保护模式
  # 1. 加载全局描述符表(GDT)
  # 2. 设置CR0的PE位
  # -------------------------  lgdt    gdtdesc
  movl    %cr0, %eax
  orl     $CR0_PE, %eax
  movl    %eax, %cr0

//PAGEBREAK!
  # Complete the transition to 32-bit protected mode by using a long jmp
  # to reload %cs and %eip.  The segment descriptors are set up with no
# ---------------------------------------------------
  # 阶段4：跳转到32位代码段
  # 使用长跳转清除预取指令队列
  # ---------------------------------------------------  # translation, so that the mapping is still the identity mapping.
  ljmp    $(SEG_KCODE<<3), $start32
# ---------------------------------------------------
  # 阶段5：设置保护模式下的数据段寄存器
  # 使用GDT中定义的数据段选择子
  # ---------------------------------------------------

.code32  # Tell assembler to generate 32-bit code now.
start32:
  # Set up the protected-mode data segment registers
  movw    $(SEG_KDATA<<3), %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %ss                # -> SS: Stack Segment
  movw    $0, %ax                 # Zero segments not ready for use
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS
# ---------------------------------------------------
  # 阶段6：设置栈指针并调用C代码
  # ---------------------------------------------------
  # Set up the stack pointer and call into C.
  movl    $start, %esp
  call    bootmain

  # If bootmain returns (it shouldn't), trigger a Bochs
  # breakpoint if running under Bochs, then loop.
  movw    $0x8a01, %ax            # 0x8a00 -> port 0x8a00
  movw    %ax, %dx
  outw    %ax, %dx
  movw    $0x8ae1, %ax            # 0x8ae0 -> port 0x8a00
  outw    %ax, %dx
spin:
  jmp     spin

# Bootstrap GDT
.p3align 2                                # force 4 byte alignment
gdt:
  SEG_NULLASM                             # null seg
  SEG_ASM(STA_X|STA_R, 0x1, 0xffffffff)   # code seg
  SEG_ASM(STA_W, 0x1, 0xffffffff)         # data seg

gdtdesc:
  .word   (gdtdesc - gdt - 2)             # sizeof(gdt) - 1
  .long   gdt                             # address gdt

