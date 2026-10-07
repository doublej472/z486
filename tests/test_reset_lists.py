#!/usr/bin/env python3
"""Regression fixtures for the reset audit itself, including its old blind spot."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent.parent / 'scripts/check_reset_lists.py'
spec = importlib.util.spec_from_file_location('reset_lists', SCRIPT)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def ff(reset, normal):
    return f'''always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin {reset} end else begin {normal} end
    end'''


class ResetAudit(unittest.TestCase):
    def missing(self, src):
        return {sig for _, sig in audit.findings(src)}

    def test_endcase_does_not_end_block(self):
        self.assertEqual(self.missing(ff('a <= 0;', '''
            case (sel) 0: a <= 1; default: a <= 0; endcase
            missing <= 1;''')), {'missing'})

    def test_case_item_assignments(self):
        self.assertEqual(self.missing(ff('a <= 0;', '''
            unique casez (sel)
                0, 1: begin a <= 1; missing <= 1; end
                default: a <= 0;
            endcase''')), {'missing'})

    def test_comments_strings_identifiers(self):
        self.assertEqual(self.missing(ff('weekend <= 0;', '''
            // end begin missing <= 9;
            /* endcase begin fake <= 2; */
            $display("end begin fake <= 3;");
            weekend <= 1; beginning <= 2;''')), {'beginning'})

    def test_comparison_is_not_assignment(self):
        self.assertEqual(self.missing(ff('a <= 0;', '''
            if (limit <= bound) a <= (other <= 2);
            while (counter <= 5) a <= 2;''')), set())

    def test_unbraced_reset_and_else_if(self):
        src = '''always_ff @(posedge clk) if (!reset_n) a <= 0;
                 else if (ready) begin a <= 1; missing <= 2; end'''
        self.assertEqual(self.missing(src), {'missing'})

    def test_inverse_reset_condition(self):
        src = '''always_ff @(posedge clk) begin
                 if (reset_n) begin a <= 1; missing <= 2; end
                 else a <= 0; end'''
        self.assertEqual(self.missing(src), {'missing'})

    def test_partial_struct_reset(self):
        self.assertEqual(self.missing(ff('state.valid <= 0;',
            'state.valid <= 1; state.data <= 2;')), {'state.data'})

    def test_whole_struct_reset(self):
        self.assertEqual(self.missing(ff("state <= '0;",
            'state.valid <= 1; state.data <= 2;')), set())

    def test_multidimensional_array_and_concat(self):
        self.assertEqual(self.missing(ff("{a, b[7:0]} <= '0;",
            'a <= 1; b[index[2:0]][7:0] <= 2; mem[row][col] <= 3;')), {'mem'})

    def test_loops_and_named_blocks(self):
        self.assertEqual(self.missing(ff('a <= 0;', '''
            begin : example
                for (int i = 0; i < 4; i++) a[i] <= 0;
                repeat (2) missing <= 1;
            end : example''')), {'missing'})

    def test_assignment_after_reset_pair(self):
        src = '''always_ff @(posedge clk) begin
                 if (reset) a <= 0; else a <= 1;
                 missing <= 2; end'''
        self.assertEqual(self.missing(src), {'missing'})

    def test_separate_always_blocks(self):
        self.assertEqual(self.missing(ff('a <= 0;', 'a <= 1;') + '\n' +
            ff('b <= 0;', 'b <= 1; missing <= 2;')), {'missing'})

    def test_cli_fails_on_gap(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'fixture.sv').write_text(ff('a <= 0;', 'missing <= 1;'))
            r = subprocess.run(['python3', str(SCRIPT), '--root', d],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 1)
            self.assertIn('missing is assigned but never reset', r.stdout)

    def test_cli_fails_on_malformed_block(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'fixture.sv').write_text('always_ff @(posedge clk) begin')
            r = subprocess.run(['python3', str(SCRIPT), '--root', d],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 1)
            self.assertIn('PARSE ERROR', r.stdout)


if __name__ == '__main__':
    unittest.main()
