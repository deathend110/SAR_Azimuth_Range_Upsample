function title_text = build_exp2_mechanism_figure_title()
% 返回实验二二维机制图标题，保持为 char，彻底避开 sprintf / string 的格式兼容性问题。
title_text = ['Experiment 2: Actual 2D Spectra from Real Pipeline Data' char(10) ...
    'Top row = Node-1 residual spectra; bottom row = Node-1 bidirectional + Node-2 RC comparison'];
end
