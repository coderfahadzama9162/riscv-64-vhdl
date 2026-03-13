-- ============================================================
-- RISC-V 64-bit Memory Interface
-- Load: LB, LH, LW, LD, LBU, LHU, LWU
-- Store: SB, SH, SW, SD
-- Byte-enable generation for sub-word stores
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv64_pkg.all;

entity mem_interface is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        -- CPU side
        addr      : in  word64_t;
        wdata     : in  word64_t;
        funct3    : in  std_logic_vector(2 downto 0);
        mem_read  : in  std_logic;
        mem_write : in  std_logic;
        rdata     : out word64_t;
        -- Memory bus (64-bit wide, byte-enabled)
        mem_addr  : out word64_t;
        mem_wdata : out word64_t;
        mem_ben   : out std_logic_vector(7 downto 0);
        mem_we    : out std_logic;
        mem_re    : out std_logic;
        mem_rdata : in  word64_t
    );
end entity mem_interface;

architecture rtl of mem_interface is

    signal byte_off : std_logic_vector(2 downto 0);
    signal raw      : word64_t;

begin

    byte_off <= addr(2 downto 0);

    -- ---- Address (aligned to 8 bytes) ----
    mem_addr  <= addr(63 downto 3) & "000";
    mem_we    <= mem_write;
    mem_re    <= mem_read;
    raw       <= mem_rdata;

    -- ---- Write data alignment & byte enables ----
    process(funct3, wdata, byte_off)
        variable data  : word64_t;
        variable bsel  : std_logic_vector(7 downto 0);
        variable boff  : integer range 0 to 7;
    begin
        boff := to_integer(unsigned(byte_off));
        data := (others => '0');
        bsel := (others => '0');

        case funct3 is
            when F3_BYTE =>     -- SB
                data(boff*8+7 downto boff*8) := wdata(7 downto 0);
                bsel(boff) := '1';
            when F3_HALF =>     -- SH
                data(boff*8+15 downto boff*8) := wdata(15 downto 0);
                bsel(boff+1) := '1';
                bsel(boff)   := '1';
            when F3_WORD =>     -- SW
                data(boff*8+31 downto boff*8) := wdata(31 downto 0);
                bsel(boff+3) := '1';
                bsel(boff+2) := '1';
                bsel(boff+1) := '1';
                bsel(boff)   := '1';
            when F3_DWORD =>    -- SD
                data := wdata;
                bsel := (others => '1');
            when others =>
                data := wdata;
                bsel := (others => '1');
        end case;

        mem_wdata <= data;
        mem_ben   <= bsel;
    end process;

    -- ---- Read data extraction & sign extension ----
    process(funct3, raw, byte_off)
        variable boff : integer range 0 to 7;
        variable b    : std_logic_vector(7 downto 0);
        variable h    : std_logic_vector(15 downto 0);
        variable w    : std_logic_vector(31 downto 0);
    begin
        boff := to_integer(unsigned(byte_off));
        b    := raw(boff*8+7  downto boff*8);
        h    := raw(boff*8+15 downto boff*8);
        w    := raw(boff*8+31 downto boff*8);

        case funct3 is
            when F3_BYTE  => rdata <= sign_extend(b,  64);   -- LB
            when F3_HALF  => rdata <= sign_extend(h,  64);   -- LH
            when F3_WORD  => rdata <= sign_extend(w,  64);   -- LW
            when F3_DWORD => rdata <= raw;                    -- LD
            when F3_BYTEU => rdata <= to_word64(b);          -- LBU
            when F3_HALFU => rdata <= to_word64(h);          -- LHU
            when F3_WORDU => rdata <= to_word64(w);          -- LWU
            when others   => rdata <= raw;
        end case;
    end process;

end architecture rtl;