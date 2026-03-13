-- ============================================================
-- RISC-V 64-bit Instruction Decoder
-- Supports: R, I, S, B, U, J instruction formats
-- RV64I + M extension
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv64_pkg.all;

entity decoder is
    port (
        instr   : in  word32_t;
        pc      : in  word64_t;
        decoded : out decoded_instr_t
    );
end entity decoder;

architecture rtl of decoder is

    signal opcode : std_logic_vector(6 downto 0);
    signal rd     : std_logic_vector(4 downto 0);
    signal rs1    : std_logic_vector(4 downto 0);
    signal rs2    : std_logic_vector(4 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);

    -- Immediate extraction signals
    signal imm_i  : word64_t;
    signal imm_s  : word64_t;
    signal imm_b  : word64_t;
    signal imm_u  : word64_t;
    signal imm_j  : word64_t;

begin

    -- ---- Field extraction ----
    opcode <= instr(6  downto 0);
    rd     <= instr(11 downto 7);
    funct3 <= instr(14 downto 12);
    rs1    <= instr(19 downto 15);
    rs2    <= instr(24 downto 20);
    funct7 <= instr(31 downto 25);

    -- ---- Immediate decoders (sign-extended to 64 bits) ----

    -- I-type: instr[31:20]
    imm_i <= (63 downto 12 => instr(31)) & instr(31 downto 20);

    -- S-type: instr[31:25] | instr[11:7]
    imm_s <= (63 downto 12 => instr(31)) & instr(31 downto 25) & instr(11 downto 7);

    -- B-type: instr[31]|instr[7]|instr[30:25]|instr[11:8]|0
    imm_b <= (63 downto 13 => instr(31)) & instr(31) & instr(7) &
             instr(30 downto 25) & instr(11 downto 8) & '0';

    -- U-type: instr[31:12] << 12
    imm_u <= (63 downto 32 => instr(31)) & instr(31 downto 12) & x"000";

    -- J-type: instr[31]|instr[19:12]|instr[20]|instr[30:21]|0
    imm_j <= (63 downto 21 => instr(31)) & instr(31) & instr(19 downto 12) &
             instr(20) & instr(30 downto 21) & '0';

    -- ---- Main decode logic ----
    process(opcode, rd, rs1, rs2, funct3, funct7,
            imm_i, imm_s, imm_b, imm_u, imm_j, instr)
        variable d : decoded_instr_t;
    begin
        -- Defaults
        d.opcode    := opcode;
        d.rd        := rd;
        d.rs1       := rs1;
        d.rs2       := rs2;
        d.funct3    := funct3;
        d.funct7    := funct7;
        d.imm       := (others => '0');
        d.alu_op    := ALU_ADD;
        d.use_imm   := '0';
        d.reg_write := '0';
        d.mem_read  := '0';
        d.mem_write := '0';
        d.branch    := '0';
        d.jump      := '0';
        d.is_word32 := '0';
        d.illegal   := '0';

        case opcode is

            -- ================================================
            -- LUI: Load Upper Immediate
            -- ================================================
            when OP_LUI =>
                d.imm       := imm_u;
                d.alu_op    := ALU_LUI;
                d.use_imm   := '1';
                d.reg_write := '1';

            -- ================================================
            -- AUIPC: Add Upper Immediate to PC
            -- ================================================
            when OP_AUIPC =>
                d.imm       := imm_u;
                d.alu_op    := ALU_AUIPC;
                d.use_imm   := '1';
                d.reg_write := '1';

            -- ================================================
            -- JAL: Jump and Link
            -- ================================================
            when OP_JAL =>
                d.imm       := imm_j;
                d.alu_op    := ALU_ADD;
                d.use_imm   := '1';
                d.reg_write := '1';
                d.jump      := '1';

            -- ================================================
            -- JALR: Jump and Link Register
            -- ================================================
            when OP_JALR =>
                d.imm       := imm_i;
                d.alu_op    := ALU_ADD;
                d.use_imm   := '1';
                d.reg_write := '1';
                d.jump      := '1';

            -- ================================================
            -- BRANCH: BEQ, BNE, BLT, BGE, BLTU, BGEU
            -- ================================================
            when OP_BRANCH =>
                d.imm    := imm_b;
                d.branch := '1';
                case funct3 is
                    when F3_BEQ  => null;
                    when F3_BNE  => null;
                    when F3_BLT  => null;
                    when F3_BGE  => null;
                    when F3_BLTU => null;
                    when F3_BGEU => null;
                    when others  => d.illegal := '1';
                end case;

            -- ================================================
            -- LOAD: LB, LH, LW, LD, LBU, LHU, LWU
            -- ================================================
            when OP_LOAD =>
                d.imm       := imm_i;
                d.alu_op    := ALU_ADD;
                d.use_imm   := '1';
                d.reg_write := '1';
                d.mem_read  := '1';
                case funct3 is
                    when F3_BYTE | F3_HALF | F3_WORD | F3_DWORD |
                         F3_BYTEU | F3_HALFU | F3_WORDU => null;
                    when others => d.illegal := '1';
                end case;

            -- ================================================
            -- STORE: SB, SH, SW, SD
            -- ================================================
            when OP_STORE =>
                d.imm       := imm_s;
                d.alu_op    := ALU_ADD;
                d.use_imm   := '1';
                d.mem_write := '1';
                case funct3 is
                    when F3_BYTE | F3_HALF | F3_WORD | F3_DWORD => null;
                    when others => d.illegal := '1';
                end case;

            -- ================================================
            -- OP-IMM: ADDI, SLTI, SLTIU, XORI, ORI, ANDI,
            --         SLLI, SRLI, SRAI
            -- ================================================
            when OP_OPIMM =>
                d.imm       := imm_i;
                d.use_imm   := '1';
                d.reg_write := '1';
                case funct3 is
                    when F3_ADD_SUB => d.alu_op := ALU_ADD;
                    when F3_SLL     => d.alu_op := ALU_SLL;
                    when F3_SLT     => d.alu_op := ALU_SLT;
                    when F3_SLTU    => d.alu_op := ALU_SLTU;
                    when F3_XOR     => d.alu_op := ALU_XOR;
                    when F3_SRL_SRA =>
                        if funct7(5) = '1' then d.alu_op := ALU_SRA;
                        else                    d.alu_op := ALU_SRL;
                        end if;
                    when F3_OR      => d.alu_op := ALU_OR;
                    when F3_AND     => d.alu_op := ALU_AND;
                    when others     => d.illegal := '1';
                end case;

            -- ================================================
            -- OP-IMM-32: ADDIW, SLLIW, SRLIW, SRAIW
            -- ================================================
            when OP_OPIMM32 =>
                d.imm       := imm_i;
                d.use_imm   := '1';
                d.reg_write := '1';
                d.is_word32 := '1';
                case funct3 is
                    when F3_ADD_SUB => d.alu_op := ALU_ADD32;
                    when F3_SLL     => d.alu_op := ALU_SLL32;
                    when F3_SRL_SRA =>
                        if funct7(5) = '1' then d.alu_op := ALU_SRA32;
                        else                    d.alu_op := ALU_SRL32;
                        end if;
                    when others => d.illegal := '1';
                end case;

            -- ================================================
            -- OP: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA,
            --     OR, AND + M-extension MUL/DIV/REM
            -- ================================================
            when OP_OP =>
                d.reg_write := '1';
                if funct7 = F7_MEXT then
                    -- M-extension
                    case funct3 is
                        when F3_MUL    => d.alu_op := ALU_MUL;
                        when F3_MULH   => d.alu_op := ALU_MULH;
                        when F3_MULHSU => d.alu_op := ALU_MULHSU;
                        when F3_MULHU  => d.alu_op := ALU_MULHU;
                        when F3_DIV    => d.alu_op := ALU_DIV;
                        when F3_DIVU   => d.alu_op := ALU_DIVU;
                        when F3_REM    => d.alu_op := ALU_REM;
                        when F3_REMU   => d.alu_op := ALU_REMU;
                        when others    => d.illegal := '1';
                    end case;
                elsif funct7 = F7_NORMAL or funct7 = F7_ALT then
                    case funct3 is
                        when F3_ADD_SUB =>
                            if funct7(5) = '1' then d.alu_op := ALU_SUB;
                            else                    d.alu_op := ALU_ADD;
                            end if;
                        when F3_SLL     => d.alu_op := ALU_SLL;
                        when F3_SLT     => d.alu_op := ALU_SLT;
                        when F3_SLTU    => d.alu_op := ALU_SLTU;
                        when F3_XOR     => d.alu_op := ALU_XOR;
                        when F3_SRL_SRA =>
                            if funct7(5) = '1' then d.alu_op := ALU_SRA;
                            else                    d.alu_op := ALU_SRL;
                            end if;
                        when F3_OR      => d.alu_op := ALU_OR;
                        when F3_AND     => d.alu_op := ALU_AND;
                        when others     => d.illegal := '1';
                    end case;
                else
                    d.illegal := '1';
                end if;

            -- ================================================
            -- OP-32: ADDW, SUBW, SLLW, SRLW, SRAW + MULW etc.
            -- ================================================
            when OP_OP32 =>
                d.reg_write := '1';
                d.is_word32 := '1';
                if funct7 = F7_MEXT then
                    case funct3 is
                        when F3_MUL  => d.alu_op := ALU_MUL;
                        when F3_DIV  => d.alu_op := ALU_DIV;
                        when F3_DIVU => d.alu_op := ALU_DIVU;
                        when F3_REM  => d.alu_op := ALU_REM;
                        when F3_REMU => d.alu_op := ALU_REMU;
                        when others  => d.illegal := '1';
                    end case;
                else
                    case funct3 is
                        when F3_ADD_SUB =>
                            if funct7(5) = '1' then d.alu_op := ALU_SUB32;
                            else                    d.alu_op := ALU_ADD32;
                            end if;
                        when F3_SLL     => d.alu_op := ALU_SLL32;
                        when F3_SRL_SRA =>
                            if funct7(5) = '1' then d.alu_op := ALU_SRA32;
                            else                    d.alu_op := ALU_SRL32;
                            end if;
                        when others => d.illegal := '1';
                    end case;
                end if;

            -- ================================================
            -- SYSTEM: ECALL, EBREAK (minimal)
            -- ================================================
            when OP_SYSTEM =>
                null; -- handled externally

            -- ================================================
            -- FENCE (NOP for single-core)
            -- ================================================
            when OP_FENCE =>
                null;

            when others =>
                d.illegal := '1';

        end case;

        decoded <= d;
    end process;

end architecture rtl;