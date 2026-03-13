-- ============================================================
-- RISC-V 64-bit Hazard Detection & Forwarding Unit
-- Data hazard detection (load-use)
-- EX/MEM/WB forwarding paths
-- Control hazard (flush on branch/jump)
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv64_pkg.all;

entity hazard_unit is
    port (
        -- ID/EX stage
        id_rs1       : in  std_logic_vector(4 downto 0);
        id_rs2       : in  std_logic_vector(4 downto 0);
        -- EX/MEM stage
        ex_rd        : in  std_logic_vector(4 downto 0);
        ex_reg_write : in  std_logic;
        ex_mem_read  : in  std_logic;
        -- MEM/WB stage
        mem_rd       : in  std_logic_vector(4 downto 0);
        mem_reg_write: in  std_logic;
        -- WB stage
        wb_rd        : in  std_logic_vector(4 downto 0);
        wb_reg_write : in  std_logic;
        -- Control
        branch_taken : in  std_logic;
        jump         : in  std_logic;
        -- Outputs
        stall        : out std_logic;
        flush_if_id  : out std_logic;
        flush_id_ex  : out std_logic;
        -- Forwarding selects (00=reg, 01=MEM/WB, 10=EX/MEM)
        fwd_a        : out std_logic_vector(1 downto 0);
        fwd_b        : out std_logic_vector(1 downto 0)
    );
end entity hazard_unit;

architecture rtl of hazard_unit is

    signal load_use_hazard : std_logic;

begin

    -- Load-use hazard: EX stage has a load, and ID stage reads that register
    load_use_hazard <= '1' when (ex_mem_read = '1' and
                                 (ex_rd = id_rs1 or ex_rd = id_rs2) and
                                 ex_rd /= "00000")
                           else '0';

    stall       <= load_use_hazard;
    flush_if_id <= branch_taken or jump;
    flush_id_ex <= load_use_hazard or branch_taken or jump;

    -- ---- RS1 Forwarding ----
    process(id_rs1, ex_rd, ex_reg_write, mem_rd, mem_reg_write,
            wb_rd, wb_reg_write)
    begin
        fwd_a <= "00"; -- default: register file
        if (ex_reg_write = '1' and ex_rd /= "00000" and ex_rd = id_rs1) then
            fwd_a <= "10";  -- forward from EX/MEM
        elsif (mem_reg_write = '1' and mem_rd /= "00000" and mem_rd = id_rs1) then
            fwd_a <= "01";  -- forward from MEM/WB
        elsif (wb_reg_write = '1' and wb_rd /= "00000" and wb_rd = id_rs1) then
            fwd_a <= "11";  -- forward from WB
        end if;
    end process;

    -- ---- RS2 Forwarding ----
    process(id_rs2, ex_rd, ex_reg_write, mem_rd, mem_reg_write,
            wb_rd, wb_reg_write)
    begin
        fwd_b <= "00";
        if (ex_reg_write = '1' and ex_rd /= "00000" and ex_rd = id_rs2) then
            fwd_b <= "10";
        elsif (mem_reg_write = '1' and mem_rd /= "00000" and mem_rd = id_rs2) then
            fwd_b <= "01";
        elsif (wb_reg_write = '1' and wb_rd /= "00000" and wb_rd = id_rs2) then
            fwd_b <= "11";
        end if;
    end process;

end architecture rtl;