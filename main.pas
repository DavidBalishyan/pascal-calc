program calculator;

uses
    x, xlib, xatom, xutil, keysym, strings;

const
    WIN_W = 272;
    WIN_H = 296;
    MARGIN = 10;
    GAP = 4;
    BTN_W = 58;
    BTN_H = 36;
    DISP_H = 44;
    COLS = 4;
    ROWS = 5;
    MAX_DIGITS = 24;
    NUM_BTNS = 18;

type
    TCalcOp = (opNone, opAdd, opSub, opMul, opDiv);

    TBtnDef = record
        lbl: array[0..3] of Char;
        col, row, span: Integer;
        cmd: Char;
    end;

var
    dpy: PDisplay;
    win: TWindow;
    gc: TGC;
    scr: Integer;
    ev: TXEvent;
    running: Boolean;

    pixWhite: QWord;
    pixBlack: QWord;
    pixGray: QWord;
    pixDispBg: QWord;
    pixBtnText: QWord;

    font: PXFontStruct;

    buf: array[0..MAX_DIGITS] of Char;
    acc: Double;
    pendingOp: TCalcOp;
    fresh: Boolean;
    hadError: Boolean;
    hasDot: Boolean;

    btns: array[0..NUM_BTNS - 1] of TBtnDef;

function disp_area_x: Integer; forward;
function disp_area_y: Integer; forward;
function disp_area_w: Integer; forward;
function disp_area_h: Integer; forward;

function get_btn_x(b: TBtnDef): Integer;
begin
    get_btn_x := MARGIN + b.col * (BTN_W + GAP);
end;

function get_btn_y(b: TBtnDef): Integer;
begin
    get_btn_y := MARGIN + DISP_H + GAP + b.row * (BTN_H + GAP);
end;

function get_btn_w(b: TBtnDef): Integer;
begin
    get_btn_w := b.span * BTN_W + (b.span - 1) * GAP;
end;

function str_len(p: PChar): Integer;
var
    i: Integer;
begin
    i := 0;
    while p[i] <> #0 do
        i := i + 1;
    str_len := i;
end;

function str_chr(p: PChar; ch: Char): Boolean;
var
    i: Integer;
begin
    i := 0;
    while p[i] <> #0 do
    begin
        if p[i] = ch then
        begin
            str_chr := True;
            Exit;
        end;
        i := i + 1;
    end;
    str_chr := False;
end;

procedure set_color(pixel: QWord);
begin
    XSetForeground(dpy, gc, pixel);
end;

procedure draw_rect(x, y, w, h: Integer);
begin
    XDrawRectangle(dpy, win, gc, x, y, w, h);
end;

procedure fill_rect(x, y, w, h: Integer);
begin
    XFillRectangle(dpy, win, gc, x, y, w, h);
end;

procedure draw_text(x, y: Integer; s: PChar; len: Integer);
begin
    XDrawString(dpy, win, gc, x, y, s, len);
end;

procedure draw_button(b: TBtnDef);
var
    x, y, w, h, tx, ty, l: Integer;
begin
    x := get_btn_x(b);
    y := get_btn_y(b);
    w := get_btn_w(b);
    h := BTN_H;

    set_color(pixGray);
    fill_rect(x + 1, y + 1, w - 2, h - 2);
    set_color(pixBlack);
    draw_rect(x, y, w, h);

    l := str_len(b.lbl);
    set_color(pixBtnText);
    tx := x + (w - l * 7) div 2;
    ty := y + (h + 12) div 2;
    draw_text(tx, ty, b.lbl, l);
end;

procedure draw_display;
var
    dx, dy, dw, dh, tx, ty, l: Integer;
begin
    dx := disp_area_x;
    dy := disp_area_y;
    dw := disp_area_w;
    dh := disp_area_h;

    set_color(pixDispBg);
    fill_rect(dx + 1, dy + 1, dw - 2, dh - 2);
    set_color(pixBlack);
    draw_rect(dx, dy, dw, dh);

    l := str_len(buf);
    set_color(pixBlack);
    tx := dx + dw - 8 - l * 7;
    if tx < dx + 4 then
        tx := dx + 4;
    ty := dy + (dh + 12) div 2;
    draw_text(tx, ty, buf, l);
end;

procedure draw_all;
var
    i: Integer;
begin
    set_color(pixWhite);
    fill_rect(0, 0, WIN_W, WIN_H);

    draw_display;

    for i := 0 to NUM_BTNS - 1 do
        draw_button(btns[i]);

    XFlush(dpy);
end;

function find_button(mx, my: Integer): Integer;
var
    i, x, y, w, h: Integer;
begin
    for i := 0 to NUM_BTNS - 1 do
    begin
        x := get_btn_x(btns[i]);
        y := get_btn_y(btns[i]);
        w := get_btn_w(btns[i]);
        h := BTN_H;
        if (mx >= x) and (mx <= x + w) and (my >= y) and (my <= y + h) then
        begin
            find_button := i;
            Exit;
        end;
    end;
    find_button := -1;
end;

function parse_buf: Double;
var
    v: Double;
    code: Integer;
begin
    Val(buf, v, code);
    if code <> 0 then
        parse_buf := 0.0
    else
        parse_buf := v;
end;

function count_zeros_end(p: PChar; len: Integer): Integer;
var
    i, dot: Integer;
begin
    dot := -1;
    for i := 0 to len - 1 do
        if p[i] = '.' then
            dot := i;
    if dot < 0 then
    begin
        count_zeros_end := 0;
        Exit;
    end;
    i := len - 1;
    while (i > dot) and (p[i] = '0') do
        i := i - 1;
    count_zeros_end := len - 1 - i;
end;

procedure update_buf_from_val(v: Double);
var
    s: array[0..31] of Char;
    i, n: Integer;
begin
    Str(v:0:10, s);
    i := 0;
    while s[i] <> #0 do
        i := i + 1;
    n := i;

    n := n - count_zeros_end(s, n);
    if (n > 0) and (s[n - 1] = '.') then
        n := n - 1;
    if n = 0 then
    begin
        buf[0] := '0';
        buf[1] := #0;
    end
    else
    begin
        for i := 0 to n - 1 do
            buf[i] := s[i];
        buf[n] := #0;
    end;
    hasDot := str_chr(buf, '.');
end;

procedure clear_all;
begin
    buf[0] := '0';
    buf[1] := #0;
    acc := 0.0;
    pendingOp := opNone;
    fresh := True;
    hadError := False;
    hasDot := False;
end;

function compute(a, b: Double; op: TCalcOp; var res: Double): Boolean;
begin
    case op of
        opAdd: res := a + b;
        opSub: res := a - b;
        opMul: res := a * b;
        opDiv:
            if b = 0.0 then
            begin
                compute := False;
                Exit;
            end
            else
                res := a / b;
        else
            res := b;
    end;
    compute := True;
end;

procedure do_digit(d: Char);
var
    l: Integer;
begin
    if hadError then
        clear_all;
    l := str_len(buf);
    if fresh or ((l = 1) and (buf[0] = '0') and not hasDot) then
    begin
        buf[0] := d;
        buf[1] := #0;
        fresh := False;
    end
    else if l < MAX_DIGITS - 1 then
    begin
        buf[l] := d;
        buf[l + 1] := #0;
    end;
end;

procedure do_decimal;
var
    l: Integer;
begin
    if hadError then
        clear_all;
    l := str_len(buf);
    if fresh then
    begin
        buf[0] := '0';
        buf[1] := '.';
        buf[2] := #0;
        fresh := False;
        hasDot := True;
    end
    else if not hasDot then
    begin
        if l < MAX_DIGITS - 1 then
        begin
            buf[l] := '.';
            buf[l + 1] := #0;
            hasDot := True;
        end;
    end;
end;

procedure do_op(op: TCalcOp);
var
    cur, res: Double;
begin
    if hadError then
    begin
        clear_all;
        Exit;
    end;

    cur := parse_buf;
    if pendingOp <> opNone then
    begin
        if not compute(acc, cur, pendingOp, res) then
        begin
            StrCopy(buf, 'Error');
            hadError := True;
            pendingOp := opNone;
            fresh := True;
            Exit;
        end;
        acc := res;
        update_buf_from_val(acc);
    end
    else
        acc := cur;

    pendingOp := op;
    fresh := True;
end;

procedure do_equals;
var
    cur, res: Double;
begin
    if hadError then
    begin
        clear_all;
        Exit;
    end;

    if pendingOp <> opNone then
    begin
        cur := parse_buf;
        if not compute(acc, cur, pendingOp, res) then
        begin
            StrCopy(buf, 'Error');
            hadError := True;
            pendingOp := opNone;
            fresh := True;
            Exit;
        end;
        acc := res;
        update_buf_from_val(acc);
        pendingOp := opNone;
        fresh := True;
    end;
end;

procedure init_buttons;
    procedure add(idx: Integer; lbl: PChar; col, row, span: Integer; cmd: Char);
    var
        i: Integer;
    begin
        for i := 0 to 3 do
        begin
            if lbl[i] <> #0 then
                btns[idx].lbl[i] := lbl[i]
            else
            begin
                btns[idx].lbl[i] := #0;
                Break;
            end;
        end;
        btns[idx].col := col;
        btns[idx].row := row;
        btns[idx].span := span;
        btns[idx].cmd := cmd;
    end;
begin
    add(0, '7', 0, 0, 1, '7');
    add(1, '8', 1, 0, 1, '8');
    add(2, '9', 2, 0, 1, '9');
    add(3, '/', 3, 0, 1, '/');
    add(4, '4', 0, 1, 1, '4');
    add(5, '5', 1, 1, 1, '5');
    add(6, '6', 2, 1, 1, '6');
    add(7, '*', 3, 1, 1, '*');
    add(8, '1', 0, 2, 1, '1');
    add(9, '2', 1, 2, 1, '2');
    add(10, '3', 2, 2, 1, '3');
    add(11, '-', 3, 2, 1, '-');
    add(12, '0', 0, 3, 1, '0');
    add(13, '.', 1, 3, 1, '.');
    add(14, '=', 2, 3, 2, '=');
    add(15, '+', 3, 3, 1, '+');
    add(16, 'C', 3, 4, 1, 'C');
    add(17, 'Q', 0, 4, 2, 'Q');
end;

function char_to_op(ch: Char): TCalcOp;
begin
    case ch of
        '+': char_to_op := opAdd;
        '-': char_to_op := opSub;
        '*': char_to_op := opMul;
        '/': char_to_op := opDiv;
        else char_to_op := opNone;
    end;
end;

procedure handle_cmd(cmd: Char);
begin
    if (cmd >= '0') and (cmd <= '9') then
        do_digit(cmd)
    else if cmd = '.' then
        do_decimal
    else if (cmd = '+') or (cmd = '-') or (cmd = '*') or (cmd = '/') then
        do_op(char_to_op(cmd))
    else if cmd = '=' then
        do_equals
    else if cmd = 'C' then
        clear_all
    else if cmd = 'Q' then
        running := False;
end;

procedure handle_key(ks: TKeySym);
begin
    case ks of
        XK_0, XK_KP_0: handle_cmd('0');
        XK_1, XK_KP_1: handle_cmd('1');
        XK_2, XK_KP_2: handle_cmd('2');
        XK_3, XK_KP_3: handle_cmd('3');
        XK_4, XK_KP_4: handle_cmd('4');
        XK_5, XK_KP_5: handle_cmd('5');
        XK_6, XK_KP_6: handle_cmd('6');
        XK_7, XK_KP_7: handle_cmd('7');
        XK_8, XK_KP_8: handle_cmd('8');
        XK_9, XK_KP_9: handle_cmd('9');
        XK_period, XK_KP_Decimal: handle_cmd('.');
        XK_plus, XK_KP_Add: handle_cmd('+');
        XK_minus, XK_KP_Subtract: handle_cmd('-');
        XK_asterisk, XK_KP_Multiply: handle_cmd('*');
        XK_slash, XK_KP_Divide: handle_cmd('/');
        XK_Return, XK_KP_Enter, XK_equal: handle_cmd('=');
        XK_Delete, XK_BackSpace: clear_all;
        XK_Escape, XK_q: running := False;
        else;
    end;
end;

procedure init_gui;
var
    cmap: TColormap;
    col: TXColor;
    exact: TXColor;
    dele: TAtom;
begin
    dpy := XOpenDisplay(nil);
    if dpy = nil then
    begin
        writeln('Error: Cannot open X display');
        Halt(1);
    end;

    scr := DefaultScreen(dpy);

    win := XCreateSimpleWindow(dpy, RootWindow(dpy, scr),
        200, 200, WIN_W, WIN_H, 1,
        BlackPixel(dpy, scr), WhitePixel(dpy, scr));

    XSelectInput(dpy, win,
        ExposureMask or ButtonPressMask or KeyPressMask or StructureNotifyMask);

    gc := XCreateGC(dpy, win, 0, nil);

    font := XLoadQueryFont(dpy, '-misc-fixed-medium-r-normal--18-*-*-*-*-*-*-*');
    if font = nil then
        font := XLoadQueryFont(dpy, 'fixed');
    if font <> nil then
        XSetFont(dpy, gc, font^.fid);

    cmap := DefaultColormap(dpy, scr);
    pixWhite := WhitePixel(dpy, scr);
    pixBlack := BlackPixel(dpy, scr);

    if XAllocNamedColor(dpy, cmap, 'gray75', @col, @exact) <> 0 then
        pixGray := col.pixel
    else
        pixGray := pixWhite;

    if XAllocNamedColor(dpy, cmap, 'gray90', @col, @exact) <> 0 then
        pixDispBg := col.pixel
    else
        pixDispBg := pixWhite;

    pixBtnText := pixBlack;

    XStoreName(dpy, win, 'Calculator');

    dele := XInternAtom(dpy, 'WM_DELETE_WINDOW', False);
    XSetWMProtocols(dpy, win, @dele, 1);

    XMapWindow(dpy, win);
end;

procedure cleanup;
begin
    if font <> nil then
        XFreeFont(dpy, font);
    XFreeGC(dpy, gc);
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
end;

procedure main_loop;
var
    idx: Integer;
    ks: TKeySym;
begin
    running := True;
    while running do
    begin
        XNextEvent(dpy, @ev);

        case ev._type of
            Expose:
                if ev.xexpose.count = 0 then
                    draw_all;
            ConfigureNotify:
                draw_all;
            ButtonPress:
                begin
                    idx := find_button(ev.xbutton.x, ev.xbutton.y);
                    if idx >= 0 then
                    begin
                        handle_cmd(btns[idx].cmd);
                        draw_display;
                        XFlush(dpy);
                    end;
                end;
            KeyPress:
                begin
                    ks := XKeycodeToKeysym(dpy, ev.xkey.keycode, 0);
                    handle_key(ks);
                    draw_display;
                    XFlush(dpy);
                end;
            ClientMessage:
                running := False;
        end;
    end;
end;

function disp_area_x: Integer;
begin
    disp_area_x := MARGIN;
end;

function disp_area_y: Integer;
begin
    disp_area_y := MARGIN;
end;

function disp_area_w: Integer;
begin
    disp_area_w := WIN_W - 2 * MARGIN;
end;

function disp_area_h: Integer;
begin
    disp_area_h := DISP_H;
end;

begin
    clear_all;
    init_buttons;
    init_gui;
    main_loop;
    cleanup;
end.
