-- ============================================================
-- RISC-V 64-bit Register File
-- 32 x 64-bit registers, x0 hardwired to zero
-- Dual read ports, single write port
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv64_pkg.all;

entity regfile is
    port (
        clk      : in  std_logic;
        -- Read port A
        rs1_addr : in  std_logic_vector(4 downto 0);
        rs1_data : out word64_t;
        -- Read port B
        rs2_addr : in  std_logic_vector(4 downto 0);
        rs2_data : out word64_t;
        -- Write port
        rd_addr  : in  std_logic_vector(4 downto 0);
        rd_data  : in  word64_t;
        rd_wen   : in  std_logic
    );
end entity regfile;

architecture rtl of regfile is

    type reg_array_t is array(0 to REG_COUNT-1) of word64_t;
    signal regs : reg_array_t := (others => (others => '0'));

begin

    -- Synchronous write
    process(clk)
    begin
        if rising_edge(clk) then
            if rd_wen = '1' and rd_addr /= "00000" then
                regs(to_integer(unsigned(rd_addr))) <= rd_data;
            end if;
        end if;
    end process;

    -- Asynchronous read with write-through forwarding
    rs1_data <= (others => '0') when rs1_addr = "00000" else
                rd_data         when (rd_wen = '1' and rd_addr = rs1_addr and rs1_addr /= "00000") else
                regs(to_integer(unsigned(rs1_addr)));

    rs2_data <= (others => '0') when rs2_addr = "00000" else
                rd_data         when (rd_wen = '1' and rd_addr = rs2_addr and rs2_addr /= "00000") else
                regs(to_integer(unsigned(rs2_addr)));

end architecture rtl;