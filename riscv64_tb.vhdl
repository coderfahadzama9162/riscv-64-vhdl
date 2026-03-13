-- ============================================================
-- RISC-V 64-bit Processor Testbench
-- Exercises: arithmetic, logical, shift, load/store,
--            branch, jump, multiply, divide, rem
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv64_pkg.all;

entity riscv64_tb is
end entity riscv64_tb;

architecture sim of riscv64_tb is

    component riscv64_core is
        generic (RESET_ADDR : word64_t := x"0000000000000000");
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            imem_addr   : out word64_t;
            imem_rdata  : in  word32_t;
            imem_req    : out std_logic;
            dmem_addr   : out word64_t;
            dmem_wdata  : out word64_t;
            dmem_rdata  : in  word64_t;
            dmem_ben    : out std_logic_vector(7 downto 0);
            dmem_we     : out std_logic;
            dmem_re     : out std_logic;
            trap        : out std_logic;
            trap_cause  : out word64_t
        );
    end component;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';

    signal imem_addr  : word64_t;
    signal imem_rdata : word32_t;
    signal imem_req   : std_logic;

    signal dmem_addr  : word64_t;
    signal dmem_wdata : word64_t;
    signal dmem_rdata : word64_t := (others => '0');
    signal dmem_ben   : std_logic_vector(7 downto 0);
    signal dmem_we    : std_logic;
    signal dmem_re    : std_logic;

    signal trap       : std_logic;
    signal trap_cause : word64_t;

    -- Simple instruction ROM (256 x 32-bit words)
    type imem_t is array(0 to 255) of word32_t;

    -- RV64 test program (assembled manually):
    -- Encoding reference:
    --   ADDI rd,rs1,imm   -> I-type
    --   ADD  rd,rs1,rs2   -> R-type
    --   SLLI rd,rs1,shamt -> I-type (shamt 6 bits)
    --   SD   rs2,imm(rs1) -> S-type
    --   LD   rd,imm(rs1)  -> I-type
    --   BEQ  rs1,rs2,off  -> B-type
    --   JAL  rd,offset    -> J-type
    --   MUL  rd,rs1,rs2   -> R-type (funct7=0000001)
    constant ROM : imem_t := (
        -- 0x000: ADDI x1, x0, 42        (x1 = 42)
        x"02A00093",
        -- 0x004: ADDI x2, x0, 10        (x2 = 10)
        x"00A00113",
        -- 0x008: ADD  x3, x1, x2        (x3 = 52)
        x"002081B3",
        -- 0x00C: SUB  x4, x1, x2        (x4 = 32)
        x"40208233",
        -- 0x010: AND  x5, x1, x2        (x5 = 8)
        x"002072B3",
        -- 0x014: OR   x6, x1, x2        (x6 = 42|10 = 58 (0x3A))
        x"00206333",
        -- 0x018: XOR  x7, x1, x2        (x7 = 42^10 = 32)
        x"002043B3",
        -- 0x01C: SLLI x8, x1, 2         (x8 = 42 << 2 = 168)
        x"00209413",
        -- 0x020: SRLI x9, x8, 1         (x9 = 168 >> 1 = 84)
        x"00145493",
        -- 0x024: SRAI x10, x8, 1        (x10 = 168 >> 1 = 84 arithmetic)
        x"40145513",
        -- 0x028: SLT  x11, x2, x1       (x11 = 1, 10 < 42)
        x"001125B3",
        -- 0x02C: SLTU x12, x2, x1       (x12 = 1)
        x"00112633",
        -- 0x030: LUI  x13, 0xABCDE      (x13 = 0xABCDE000)
        x"ABCDE6B7",
        -- 0x034: AUIPC x14, 1           (x14 = PC+0x1000 = 0x1034)
        x"00001717",
        -- 0x038: MUL  x15, x1, x2       (x15 = 42*10 = 420)  funct7=0000001
        x"022087B3",
        -- 0x03C: DIV  x16, x15, x2      (x16 = 420/10 = 42)
        x"022C4833",
        -- 0x040: REM  x17, x15, x1      (x17 = 420 rem 42 = 0)
        x"021C88B3",
        -- 0x044: ADDI x18, x0, 256      (x18 = base addr 0x100 for data)
        x"10000913",
        -- 0x048: SD   x3, 0(x18)        (mem[256] = 52)
        x"00393023",
        -- 0x04C: LD   x19, 0(x18)       (x19 = 52)
        x"00093983",
        -- 0x050: BEQ  x3, x19, +8       (branch: 52==52 -> skip next)
        x"01318463",
        -- 0x054: ADDI x20, x0, 0xFF     (NOT reached)
        x"0FF00A13",
        -- 0x058: ADDI x20, x0, 1        (x20 = 1, branch target)
        x"00100A13",
        -- 0x05C: JAL  x21, +8           (x21 = 0x60, jump to 0x064)
        x"008000EF",
        -- 0x060: ADDI x22, x0, 0xBEEF   (NOT reached)
        x"BEEF0B13",
        -- 0x064: ADDI x23, x0, 7        (x23 = 7, JAL target)
        x"00700B93",
        -- 0x068: ADDW x24, x1, x2       (x24 = 52 as 32-bit sign-extended)
        x"00208C3B",
        -- 0x06C: MULHU x25, x1, x2      (x25 = high 64 bits of 42*10)
        x"02209CB3",
        -- 0x070: EBREAK / ECALL trap (stops simulation)
        x"00100073",
        -- padding
        others => x"00000013"  -- NOP
    );

    -- Simple 64-bit data memory (1 KB)
    type dmem_t is array(0 to 127) of word64_t;
    signal dmem : dmem_t := (others => (others => '0'));

begin

    -- DUT
    U_CPU : riscv64_core
        generic map (RESET_ADDR => x"0000000000000000")
        port map (
            clk        => clk,
            rst        => rst,
            imem_addr  => imem_addr,
            imem_rdata => imem_rdata,
            imem_req   => imem_req,
            dmem_addr  => dmem_addr,
            dmem_wdata => dmem_wdata,
            dmem_rdata => dmem_rdata,
            dmem_ben   => dmem_ben,
            dmem_we    => dmem_we,
            dmem_re    => dmem_re,
            trap       => trap,
            trap_cause => trap_cause
        );

    -- 10 ns clock
    clk <= not clk after 5 ns;

    -- Reset
    process
    begin
        rst <= '1';
        wait for 25 ns;
        rst <= '0';
        wait;
    end process;

    -- Instruction memory
    imem_rdata <= ROM(to_integer(unsigned(imem_addr(9 downto 2))))
                  when to_integer(unsigned(imem_addr(9 downto 2))) < 256
                  else x"00000013";

    -- Data memory
    process(clk)
        variable idx : integer;
    begin
        if rising_edge(clk) then
            idx := to_integer(unsigned(dmem_addr(9 downto 3)));
            if dmem_we = '1' then
                -- Byte-enable write
                for i in 0 to 7 loop
                    if dmem_ben(i) = '1' then
                        dmem(idx)(i*8+7 downto i*8) <= dmem_wdata(i*8+7 downto i*8);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(9 downto 3))))
                  when dmem_re = '1' else (others => '0');

    -- Trap / end of sim monitor
    process
    begin
        wait until trap = '1';
        wait for 20 ns;
        report "=== Simulation complete: TRAP caught ===" severity note;
        report "Trap cause: " & integer'image(to_integer(unsigned(trap_cause))) severity note;
        wait for 100 ns;
        std.env.stop;
    end process;

    -- Timeout guard
    process
    begin
        wait for 10 us;
        report "=== TIMEOUT ===" severity failure;
    end process;

end architecture sim;