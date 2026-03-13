-- ============================================================
-- RISC-V 64-bit Branch Unit
-- Evaluates all branch conditions: BEQ BNE BLT BGE BLTU BGEU
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv64_pkg.all;

entity branch_unit is
    port (
        rs1_val  : in  word64_t;
        rs2_val  : in  word64_t;
        funct3   : in  std_logic_vector(2 downto 0);
        taken    : out std_logic
    );
end entity branch_unit;

architecture rtl of branch_unit is
    signal sa : signed(63 downto 0);
    signal sb : signed(63 downto 0);
    signal ua : unsigned(63 downto 0);
    signal ub : unsigned(63 downto 0);
begin
    sa <= signed(rs1_val);
    sb <= signed(rs2_val);
    ua <= unsigned(rs1_val);
    ub <= unsigned(rs2_val);

    process(funct3, sa, sb, ua, ub)
    begin
        case funct3 is
            when F3_BEQ  => taken <= '1' when ua  = ub  else '0';
            when F3_BNE  => taken <= '1' when ua /= ub  else '0';
            when F3_BLT  => taken <= '1' when sa  < sb  else '0';
            when F3_BGE  => taken <= '1' when sa >= sb  else '0';
            when F3_BLTU => taken <= '1' when ua  < ub  else '0';
            when F3_BGEU => taken <= '1' when ua >= ub  else '0';
            when others  => taken <= '0';
        end case;
    end process;
end architecture rtl;