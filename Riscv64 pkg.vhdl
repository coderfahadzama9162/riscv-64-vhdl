-- ============================================================
-- RISC-V 64-bit Processor Package
-- Supports: RV64I Base + M (Multiply/Divide) Extension
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package riscv64_pkg is

    -- ---- Data widths ----
    constant XLEN       : integer := 64;
    constant ILEN       : integer := 32;
    constant REG_COUNT  : integer := 32;
    constant ADDR_WIDTH : integer := 64;

    subtype word64_t  is std_logic_vector(63 downto 0);
    subtype word32_t  is std_logic_vector(31 downto 0);
    subtype reg_addr_t is std_logic_vector(4 downto 0);

    -- ---- Opcodes (instr[6:2]) ----
    constant OP_LOAD     : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE    : std_logic_vector(6 downto 0) := "0100011";
    constant OP_BRANCH   : std_logic_vector(6 downto 0) := "1100011";
    constant OP_JALR     : std_logic_vector(6 downto 0) := "1100111";
    constant OP_JAL      : std_logic_vector(6 downto 0) := "1101111";
    constant OP_AUIPC    : std_logic_vector(6 downto 0) := "0010111";
    constant OP_LUI      : std_logic_vector(6 downto 0) := "0110111";
    constant OP_OP       : std_logic_vector(6 downto 0) := "0110011"; -- R-type
    constant OP_OP32     : std_logic_vector(6 downto 0) := "0111011"; -- R-type 32-bit
    constant OP_OPIMM    : std_logic_vector(6 downto 0) := "0010011"; -- I-type ALU
    constant OP_OPIMM32  : std_logic_vector(6 downto 0) := "0011011"; -- I-type ALU 32-bit
    constant OP_SYSTEM   : std_logic_vector(6 downto 0) := "1110011";
    constant OP_FENCE    : std_logic_vector(6 downto 0) := "0001111";

    -- ---- funct3 codes ----
    constant F3_ADD_SUB  : std_logic_vector(2 downto 0) := "000";
    constant F3_SLL      : std_logic_vector(2 downto 0) := "001";
    constant F3_SLT      : std_logic_vector(2 downto 0) := "010";
    constant F3_SLTU     : std_logic_vector(2 downto 0) := "011";
    constant F3_XOR      : std_logic_vector(2 downto 0) := "100";
    constant F3_SRL_SRA  : std_logic_vector(2 downto 0) := "101";
    constant F3_OR       : std_logic_vector(2 downto 0) := "110";
    constant F3_AND      : std_logic_vector(2 downto 0) := "111";

    -- M-extension funct3
    constant F3_MUL      : std_logic_vector(2 downto 0) := "000";
    constant F3_MULH     : std_logic_vector(2 downto 0) := "001";
    constant F3_MULHSU   : std_logic_vector(2 downto 0) := "010";
    constant F3_MULHU    : std_logic_vector(2 downto 0) := "011";
    constant F3_DIV      : std_logic_vector(2 downto 0) := "100";
    constant F3_DIVU     : std_logic_vector(2 downto 0) := "101";
    constant F3_REM      : std_logic_vector(2 downto 0) := "110";
    constant F3_REMU     : std_logic_vector(2 downto 0) := "111";

    -- Branch funct3
    constant F3_BEQ      : std_logic_vector(2 downto 0) := "000";
    constant F3_BNE      : std_logic_vector(2 downto 0) := "001";
    constant F3_BLT      : std_logic_vector(2 downto 0) := "100";
    constant F3_BGE      : std_logic_vector(2 downto 0) := "101";
    constant F3_BLTU     : std_logic_vector(2 downto 0) := "110";
    constant F3_BGEU     : std_logic_vector(2 downto 0) := "111";

    -- Load/Store funct3
    constant F3_BYTE     : std_logic_vector(2 downto 0) := "000";
    constant F3_HALF     : std_logic_vector(2 downto 0) := "001";
    constant F3_WORD     : std_logic_vector(2 downto 0) := "010";
    constant F3_DWORD    : std_logic_vector(2 downto 0) := "011";
    constant F3_BYTEU    : std_logic_vector(2 downto 0) := "100";
    constant F3_HALFU    : std_logic_vector(2 downto 0) := "101";
    constant F3_WORDU    : std_logic_vector(2 downto 0) := "110";

    -- ---- funct7 codes ----
    constant F7_NORMAL   : std_logic_vector(6 downto 0) := "0000000";
    constant F7_ALT      : std_logic_vector(6 downto 0) := "0100000"; -- SUB, SRA
    constant F7_MEXT     : std_logic_vector(6 downto 0) := "0000001"; -- M-extension

    -- ---- ALU operations ----
    type alu_op_t is (
        ALU_ADD, ALU_SUB,
        ALU_AND, ALU_OR, ALU_XOR,
        ALU_SLL, ALU_SRL, ALU_SRA,
        ALU_SLT, ALU_SLTU,
        ALU_MUL, ALU_MULH, ALU_MULHSU, ALU_MULHU,
        ALU_DIV, ALU_DIVU, ALU_REM, ALU_REMU,
        ALU_LUI, ALU_AUIPC,
        ALU_PASS_A, ALU_PASS_B,
        ALU_ADD32, ALU_SUB32,
        ALU_SLL32, ALU_SRL32, ALU_SRA32
    );

    -- ---- Decoded instruction record ----
    type decoded_instr_t is record
        opcode    : std_logic_vector(6 downto 0);
        rd        : std_logic_vector(4 downto 0);
        rs1       : std_logic_vector(4 downto 0);
        rs2       : std_logic_vector(4 downto 0);
        funct3    : std_logic_vector(2 downto 0);
        funct7    : std_logic_vector(6 downto 0);
        imm       : std_logic_vector(63 downto 0);
        alu_op    : alu_op_t;
        -- Control signals
        use_imm   : std_logic;
        reg_write : std_logic;
        mem_read  : std_logic;
        mem_write : std_logic;
        branch    : std_logic;
        jump      : std_logic;
        is_word32 : std_logic;   -- RV64: *W instructions
        illegal   : std_logic;
    end record;

    -- ---- Pipeline stage records ----
    type if_id_t is record
        pc    : word64_t;
        instr : word32_t;
        valid : std_logic;
    end record;

    type id_ex_t is record
        pc      : word64_t;
        rs1_val : word64_t;
        rs2_val : word64_t;
        decoded : decoded_instr_t;
        valid   : std_logic;
    end record;

    type ex_mem_t is record
        pc       : word64_t;
        alu_res  : word64_t;
        rs2_val  : word64_t;
        decoded  : decoded_instr_t;
        valid    : std_logic;
    end record;

    type mem_wb_t is record
        alu_res  : word64_t;
        mem_data : word64_t;
        decoded  : decoded_instr_t;
        valid    : std_logic;
    end record;

    -- ---- Functions ----
    function sign_extend(v : std_logic_vector; width : integer) return std_logic_vector;
    function to_word64(v : std_logic_vector) return word64_t;

end package riscv64_pkg;

package body riscv64_pkg is

    function sign_extend(v : std_logic_vector; width : integer) return std_logic_vector is
        variable result : std_logic_vector(width-1 downto 0);
    begin
        result := (others => v(v'high));
        result(v'length-1 downto 0) := v;
        return result;
    end function;

    function to_word64(v : std_logic_vector) return word64_t is
        variable result : word64_t := (others => '0');
    begin
        result(v'length-1 downto 0) := v;
        return result;
    end function;

end package body riscv64_pkg;