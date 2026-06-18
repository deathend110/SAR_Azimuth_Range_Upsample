title_text = build_exp2_mechanism_figure_title();
expected_text = ['Experiment 2: Actual 2D Spectra from Real Pipeline Data' char(10) ...
    'Top row = Node-1 residual spectra; bottom row = Node-1 bidirectional + Node-2 RC comparison'];

assert(ischar(title_text), "title_text 必须是 char，避免 sprintf / sgtitle 的字符串兼容性问题。");
assert(strcmp(title_text, expected_text), "title_text 与预期完整标题不一致。");
assert(nnz(title_text == char(10)) == 1, "title_text 应只包含一个换行符。");

disp("test_exp2_build_figure_title PASS");
