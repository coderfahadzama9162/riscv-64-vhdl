-- ============================================================
-- RISC-V 64-bit ALU
-- Arithmetic: ADD, SUB, SLT, SLTU, MUL, MULH, DIV, REM
-- Logical:    AND, OR, XOR, SLL, SRL, SRA
-- RV64 word:  ADD32, SUB32, SLL32, SRL32, SRA32
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv64_pkg.all;

entity alu is
    port (
        op      : in  alu_op_t;
        a       : in  word64_t;   -- rs1 or PC
        b       : in  word64_t;   -- rs2 or immediate
        result  : out word64_t;
        zero    : out std_logic;
        neg     : out std_logic;
        overflow: out std_logic
    );
end entity alu;

architecture rtl of alu is

    signal sa  : signed(63 downto 0);
    signal sb  : signed(63 downto 0);
    signal ua  : unsigned(63 downto 0);
    signal ub  : unsigned(63 downto 0);
    signal shamt   : integer range 0 to 63;
    signal shamt32 : integer range 0 to 31;

    -- 128-bit products for MULH variants
    signal prod_ss : signed(127 downto 0);
    signal prod_su : signed(127 downto 0);
    signal prod_uu : unsigned(127 downto 0);

    -- 32-bit operand slices (sign-extended)
    signal sa32 : signed(31 downto 0);
    signal sb32 : signed(31 downto 0);
    signal res32 : signed(31 downto 0);

    signal alu_result : word64_t;

begin

    sa  <= signed(a);
    sb  <= signed(b);
    ua  <= unsigned(a);
    ub  <= unsigned(b);
    shamt   <= to_integer(unsigned(b(5 downto 0)));
    shamt32 <= to_integer(unsigned(b(4 downto 0)));

    sa32 <= signed(a(31 downto 0));
    sb32 <= signed(b(31 downto 0));

    -- ---- 128-bit multiplications ----
    prod_ss <= sa * sb;
    prod_uu <= ua * ub;
    prod_su <= signed('0' & std_logic_vector(ub)) * sa;

    -- ---- Main ALU ----
    process(op, a, b, sa, sb, ua, ub, shamt, shamt32,
            prod_ss, prod_su, prod_uu, sa32, sb32)
        variable r   : word64_t;
        variable r32 : signed(31 downto 0);
        variable div_s : signed(63 downto 0);
        variable div_u : unsigned(63 downto 0);
        variable rem_s : signed(63 downto 0);
        variable rem_u : unsigned(63 downto 0);
    begin
        r := (others => '0');

        case op is
            -- ---- Arithmetic ----
            when ALU_ADD =>
                r := std_logic_vector(ua + ub);

            when ALU_SUB =>
                r := std_logic_vector(ua - ub);

            when ALU_SLT =>
                if sa < sb then r := x"0000000000000001";
                else            r := (others => '0');
                end if;

            when ALU_SLTU =>
                if ua < ub then r := x"0000000000000001";
                else            r := (others => '0');
                end if;

            -- ---- Logical ----
            when ALU_AND => r := a and b;
            when ALU_OR  => r := a or  b;
            when ALU_XOR => r := a xor b;

            -- ---- Shifts ----
            when ALU_SLL =>
                r := std_logic_vector(shift_left(ua, shamt));

            when ALU_SRL =>
                r := std_logic_vector(shift_right(ua, shamt));

            when ALU_SRA =>
                r := std_logic_vector(shift_right(sa, shamt));

            -- ---- M-extension: Multiply ----
            when ALU_MUL =>
                r := std_logic_vector(prod_ss(63 downto 0));

            when ALU_MULH =>
                r := std_logic_vector(prod_ss(127 downto 64));

            when ALU_MULHU =>
                r := std_logic_vector(prod_uu(127 downto 64));

            when ALU_MULHSU =>
                r := std_logic_vector(prod_su(127 downto 64));

            -- ---- M-extension: Divide ----
            when ALU_DIV =>
                if sb = 0 then
                    r := (others => '1');        -- division by zero -> -1
                elsif sa = x"8000000000000000" and sb = x"FFFFFFFFFFFFFFFF" then
                    r := std_logic_vector(sa);   -- overflow
                else
                    div_s := sa / sb;
                    r := std_logic_vector(div_s);
                end if;

            when ALU_DIVU =>
                if ub = 0 then
                    r := (others => '1');        -- division by zero -> 2^64-1
                else
                    div_u := ua / ub;
                    r := std_logic_vector(div_u);
                end if;

            when ALU_REM =>
                if sb = 0 then
                    r := a;                      -- remainder by zero -> dividend
                elsif sa = x"8000000000000000" and sb = x"FFFFFFFFFFFFFFFF" then
                    r := (others => '0');        -- overflow -> 0
                else
                    rem_s := sa rem sb;
                    r := std_logic_vector(rem_s);
                end if;

            when ALU_REMU =>
                if ub = 0 then
                    r := a;                      -- remainder by zero -> dividend
                else
                    rem_u := ua rem ub;
                    r := std_logic_vector(rem_u);
                end if;

            -- ---- U-type passthrough ----
            when ALU_LUI  => r := b;             -- imm already shifted
            when ALU_AUIPC =>
                r := std_logic_vector(unsigned(a) + unsigned(b)); -- PC + imm

            when ALU_PASS_A => r := a;
            when ALU_PASS_B => r := b;

            -- ---- RV64: *W (32-bit) operations, sign-extend result ----
            when ALU_ADD32 =>
                r32 := sa32 + sb32;
                r   := std_logic_vector(resize(r32, 64));

            when ALU_SUB32 =>
                r32 := sa32 - sb32;
                r   := std_logic_vector(resize(r32, 64));

            when ALU_SLL32 =>
                r32 := shift_left(sa32, shamt32);
                r   := std_logic_vector(resize(r32, 64));

            when ALU_SRL32 =>
                r32 := signed(shift_right(unsigned(sa32), shamt32));
                r   := std_logic_vector(resize(r32, 64));

            when ALU_SRA32 =>
                r32 := shift_right(sa32, shamt32);
                r   := std_logic_vector(resize(r32, 64));

            when others => r := (others => '0');
        end case;

        alu_result <= r;
    end process;

    result   <= alu_result;
    zero     <= '1' when alu_result = x"0000000000000000" else '0';
    neg      <= alu_result(63);
    overflow <= (a(63) xnor b(63)) and (a(63) xor alu_result(63))
                when op = ALU_ADD else
                (a(63) xor  b(63)) and (a(63) xor alu_result(63))
                when op = ALU_SUB else '0';

end architecture rtl;