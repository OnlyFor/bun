const std = @import("std");
pub const css = @import("../css_parser.zig");
const bun = @import("root").bun;
const Error = css.Error;
const ArrayList = std.ArrayListUnmanaged;
const MediaList = css.MediaList;
const CustomMedia = css.CustomMedia;
const Printer = css.Printer;
const Maybe = css.Maybe;
const PrinterError = css.PrinterError;
const PrintErr = css.PrintErr;
const Dependency = css.Dependency;
const dependencies = css.dependencies;
const Url = css.css_values.url.Url;
const Size2D = css.css_values.size.Size2D;
const fontprops = css.css_properties.font;
const LayerName = css.css_rules.layer.LayerName;
const SupportsCondition = css.css_rules.supports.SupportsCondition;
const Location = css.css_rules.Location;
const Angle = css.css_values.angle.Angle;
const FontStyleProperty = css.css_properties.font.FontStyle;
const FontFamily = css.css_properties.font.FontFamily;
const FontWeight = css.css_properties.font.FontWeight;
const FontStretch = css.css_properties.font.FontStretch;
const CustomProperty = css.css_properties.custom.CustomProperty;
const CustomPropertyName = css.css_properties.custom.CustomPropertyName;

/// A property within an `@font-face` rule.
///
/// See [FontFaceRule](FontFaceRule).
pub const FontFaceProperty = union(enum) {
    /// The `src` property.
    source: ArrayList(Source),

    /// The `font-family` property.
    font_family: fontprops.FontFamily,

    /// The `font-style` property.
    font_style: FontStyle,

    /// The `font-weight` property.
    font_weight: Size2D(fontprops.FontWeight),

    /// The `font-stretch` property.
    font_stretch: Size2D(fontprops.FontStretch),

    /// The `unicode-range` property.
    unicode_range: ArrayList(UnicodeRange),

    /// An unknown or unsupported property.
    custom: css.css_properties.custom.CustomProperty,

    const This = @This();

    pub fn toCss(this: *const This, comptime W: type, dest: *Printer(W)) PrintErr!void {
        const Helpers = struct {
            pub fn writeProperty(
                d: *Printer(W),
                comptime prop: []const u8,
                value: anytype,
                comptime multi: bool,
            ) PrintErr!void {
                try d.writeStr(prop);
                try d.delm(':', false);
                if (comptime multi) {
                    const len = value.items.len;
                    for (value.items, 0..) |*val, idx| {
                        try val.toCss(W, d);
                        if (idx < len - 1) {
                            try d.delim(',', false);
                        }
                    }
                } else {
                    try value.toCss(W, d);
                }
            }
        };
        return switch (this.*) {
            .source => |value| Helpers.writeProperty(dest, "src", value, true),
            .font_family => |value| Helpers.writeProperty(dest, "font-family", value, false),
            .font_style => |value| Helpers.writeProperty(dest, "font-style", value, false),
            .font_weight => |value| Helpers.writeProperty(dest, "font-weight", value, false),
            .font_stretch => |value| Helpers.writeProperty(dest, "font-stretch", value, false),
            .unicode_range => |value| Helpers.writeProperty(dest, "unicode-range", value, false),
            .custom => |custom| {
                try dest.writeStr(this.custom.name.asStr());
                try dest.delim(':', false);
                return custom.value.toCss(W, dest, true);
            },
        };
    }
};

/// A contiguous range of Unicode code points.
///
/// Cannot be empty. Can represent a single code point when start == end.
pub const UnicodeRange = struct {
    /// Inclusive start of the range. In [0, end].
    start: u32,

    /// Inclusive end of the range. In [0, 0x10FFFF].
    end: u32,

    pub fn toCss(this: *const UnicodeRange, comptime W: type, dest: *Printer(W)) PrintErr!void {
        // Attempt to optimize the range to use question mark syntax.
        if (this.start != this.end) {
            // Find the first hex digit that differs between the start and end values.
            var shift = 24;
            var mask = 0xf << shift;
            while (shift > 0) {
                const c1 = this.start & mask;
                const c2 = this.end & mask;
                if (c1 != c2) {
                    break;
                }

                mask = mask >> 4;
                shift -= 4;
            }

            // Get the remainder of the value. This must be 0x0 to 0xf for the rest
            // of the value to use the question mark syntax.
            shift += 4;
            const remainder_mask = (1 << shift) - 1;
            const start_remainder = this.start & remainder_mask;
            const end_remainder = this.end & remainder_mask;

            if (start_remainder == 0 and end_remainder == remainder_mask) {
                const start = (this.start & !remainder_mask) >> shift;
                if (start != 0) {
                    try dest.writeFmt("U+{x}", .{start});
                } else {
                    try dest.writeStr("U+");
                }

                while (shift > 0) {
                    try dest.writeChar('?');
                    shift -= 4;
                }

                return;
            }
        }

        try dest.writeFmt("U+{x}", .{this.start});
        if (this.end != this.start) {
            try dest.writeFmt("-{x}", .{this.end});
        }
    }

    /// https://drafts.csswg.org/css-syntax/#urange-syntax
    pub fn parse(input: *css.Parser) Error!UnicodeRange {
        // <urange> =
        //   u '+' <ident-token> '?'* |
        //   u <dimension-token> '?'* |
        //   u <number-token> '?'* |
        //   u <number-token> <dimension-token> |
        //   u <number-token> <number-token> |
        //   u '+' '?'+

        try input.expectIdentMatching("u");
        const after_u = input.position();
        try parseTokens(input);

        // This deviates from the spec in case there are CSS comments
        // between tokens in the middle of one <unicode-range>,
        // but oh well…
        const concatenated_tokens = input.sliceFrom(after_u);

        const range = if (parseConcatenated(concatenated_tokens)) |range|
            range
        else
            return input.newBasicUnexpectedTokenError(.{ .ident = concatenated_tokens });

        if (range.end > 0x10FFFF or range.start > range.end) {
            return input.newBasicUnexpectedTokenError(.{ .ident = concatenated_tokens });
        }

        return range;
    }

    fn parseTokens(input: *css.Parser) Error!void {
        const tok = try input.nextIncludingWhitespace();
        switch (tok.*) {
            .dimension => try parseQuestionMarks(input),
            .number => {
                const after_number = input.state();
                const token = input.nextIncludingWhitespace() catch {
                    input.reset(&after_number);
                    return;
                };
                if (token.* == .delim and token.delim == '?') return parseQuestionMarks(input);
                if (token.* == .delim or token.* == .number) return;
                return;
            },
            .delim => {},
            else => {},
        }
        return input.newBasicUnexpectedTokenError(tok.*);
    }

    /// Consume as many '?' as possible
    fn parseQuestionMarks(input: *css.Parser) Error!void {
        while (true) {
            const start = input.state();
            if (input.nextIncludingWhitespace()) |tok| if (tok.* == .delim and tok.delim == '?') continue;
            input.reset(&start);
            return;
        }
    }

    fn parseConcatenated(_text: []const u8) Error!UnicodeRange {
        var text = if (_text.len > 0 and _text[0] == '+') _text[1..] else {
            @compileError(css.todo_stuff.errors);
        };
        const first_hex_value, const hex_digit_count = consumeHex(&text);
        const question_marks = consumeQuestionMarks(&text);
        const consumed = hex_digit_count + question_marks;

        if (consumed == 0 or consumed > 6) {
            @compileError(css.todo_stuff.errors);
        }

        if (question_marks > 0) {
            if (text.len == 0) return UnicodeRange{
                .start = first_hex_value << (question_marks * 4),
                .end = ((first_hex_value + 1) << (question_marks * 4)) - 1,
            };
        } else if (text.len == 0) {
            return UnicodeRange{
                .start = first_hex_value,
                .end = first_hex_value,
            };
        } else {
            if (text.len > 0 and text[0] == '-') {
                text = text[1..];
                const second_hex_value, const hex_digit_count2 = consumeHex(&text);
                if (hex_digit_count2 > 0 and hex_digit_count2 <= 6 and text.len == 0) {
                    return UnicodeRange{
                        .start = first_hex_value,
                        .end = second_hex_value,
                    };
                }
            }
        }
        @compileError(css.todo_stuff.errors);
    }

    fn consumeQuestionMarks(text: *[]const u8) usize {
        var question_marks = 0;
        while (bun.strings.splitFirstWithExpected(text.*, '?')) |rest| {
            question_marks += 1;
            text.* = rest;
        }
        return question_marks;
    }

    fn consumeHex(text: *[]const u8) struct { u32, usize } {
        var value = 0;
        var digits = 0;
        while (bun.strings.splitFirst(text.*)) |result| {
            if (toHexDigit(result.first)) |digit_value| {
                value = value * 0x10 + digit_value;
                digits += 1;
                text.* = result.rest;
            } else {
                break;
            }
        }
        return .{ value, digits };
    }

    fn toHexDigit(b: u8) ?u32 {
        var digit = @as(u32, b) -% @as(u32, '0');
        if (digit < 10) return digit;
        // Force the 6th bit to be set to ensure ascii is lower case.
        // digit = (@as(u32, b) | 0b10_0000).wrapping_sub('a' as u32).saturating_add(10);
        digit = (@as(u32, b) | 0b10_0000) -% (@as(u32, 'a') +% 10);
        return if (digit < 16) digit else null;
    }
};

pub const FontStyle = union(enum) {
    /// Normal font style.
    normal,

    /// Italic font style.
    italic,

    /// Oblique font style, with a custom angle.
    oblique: Size2D(css.css_values.angle.Angle),

    pub fn parse(input: *css.Parser) Error!FontStyle {
        return switch (try FontStyleProperty.parse(input)) {
            .normal => .normal,
            .italic => .italic,
            .oblique => |angle| {
                const second_angle = if (input.tryParse(css.css_values.angle.Angle.parse, .{})) |a| a else angle;
                return .{
                    .oblique = .{ angle, second_angle },
                };
            },
        };
    }

    pub fn toCss(this: *const FontStyle, comptime W: type, dest: *Printer(W)) PrintErr!void {
        switch (this) {
            .normal => try dest.writeStr("normal"),
            .italic => try dest.writeStr("italic"),
            .oblique => |angle| {
                try dest.writeStr("oblique");
                if (angle != FontStyle.defaultObliqueAngle()) {
                    try dest.writeChar(' ');
                    try angle.toCss(dest);
                }
            },
        }
    }

    fn defaultObliqueAngle() Size2D(Angle) {
        return Size2D(Angle){
            FontStyleProperty.defaultObliqueAngle(),
            FontStyleProperty.defaultObliqueAngle(),
        };
    }
};

/// A font format keyword in the `format()` function of the
/// [src](https://drafts.csswg.org/css-fonts/#src-desc)
/// property of an `@font-face` rule.
pub const FontFormat = union(enum) {
    /// A WOFF 1.0 font.
    woff,

    /// A WOFF 2.0 font.
    woff2,

    /// A TrueType font.
    truetype,

    /// An OpenType font.
    opentype,

    /// An Embedded OpenType (.eot) font.
    embedded_opentype,

    /// OpenType Collection.
    collection,

    /// An SVG font.
    svg,

    /// An unknown format.
    string: []const u8,

    pub fn parse(input: *css.Parser) Error!FontFormat {
        const s = try input.expectIdentOrString();

        if (bun.strings.eqlCaseInsensitiveASCIIICheckLength("woff", s)) {
            return .woff;
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength("woff2", s)) {
            return .woff2;
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength("truetype", s)) {
            return .truetype;
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength("opentype", s)) {
            return .opentype;
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength("embedded-opentype", s)) {
            return .embedded_opentype;
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength("collection", s)) {
            return .collection;
        } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength("svg", s)) {
            return .svg;
        } else {
            return .{ .string = s };
        }
    }

    pub fn toCss(this: *const FontFormat, comptime W: type, dest: *Printer(W)) PrintErr!void {
        // Browser support for keywords rather than strings is very limited.
        // https://developer.mozilla.org/en-US/docs/Web/CSS/@font-face/src
        switch (this) {
            .woff => try dest.writeStr("woff"),
            .woff2 => try dest.writeStr("woff2"),
            .truetype => try dest.writeStr("truetype"),
            .opentype => try dest.writeStr("opentype"),
            .embedded_opentype => try dest.writeStr("embedded-opentype"),
            .collection => try dest.writeStr("collection"),
            .svg => try dest.writeStr("svg"),
            .string => try dest.writeStr(this.string),
        }
    }
};

/// A value for the [src](https://drafts.csswg.org/css-fonts/#src-desc)
/// property in an `@font-face` rule.
pub const Source = union(enum) {
    /// A `url()` with optional format metadata.
    url: UrlSource,

    /// The `local()` function.
    local: fontprops.FontFamily,

    pub fn parse(input: *css.Parser) Error!Source {
        if (input.tryParse(UrlSource.parse, .{})) |url|
            return .{ .url = url }
        else |e| {
            _ = e; // autofix
            @compileError(css.todo_stuff.errors);
        }

        try input.expectFunctionMatching("local");
        const Fn = struct {
            pub fn parseNestedBlock(_: void, i: *css.Parser) Error!fontprops.FontFamily {
                return fontprops.FontFamily.parse(i);
            }
        };
        const local = try input.parseNestedBlock(fontprops.FontFamily, {}, Fn.parseNestedBlock);
        return .{ .local = local };
    }

    pub fn toCss(this: *const Source, comptime W: type, dest: *Printer(W)) PrintErr!void {
        switch (this) {
            .url => try this.url.toCss(dest),
            .local => {
                try dest.writeStr("local(");
                try this.local.toCss(dest);
                try dest.writeChar(')');
            },
        }
    }
};

pub const FontTechnology = enum {
    /// A font format keyword in the `format()` function of the
    /// [src](https://drafts.csswg.org/css-fonts/#src-desc)
    /// property of an `@font-face` rule.
    /// A font features tech descriptor in the `tech()`function of the
    /// [src](https://drafts.csswg.org/css-fonts/#font-features-tech-values)
    /// property of an `@font-face` rule.
    /// Supports OpenType Features.
    /// https://docs.microsoft.com/en-us/typography/opentype/spec/featurelist
    @"features-opentype",

    /// Supports Apple Advanced Typography Font Features.
    /// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM09/AppendixF.html
    @"features-aat",

    /// Supports Graphite Table Format.
    /// https://scripts.sil.org/cms/scripts/render_download.php?site_id=nrsi&format=file&media_id=GraphiteBinaryFormat_3_0&filename=GraphiteBinaryFormat_3_0.pdf
    @"features-graphite",

    /// A color font tech descriptor in the `tech()`function of the
    /// [src](https://drafts.csswg.org/css-fonts/#src-desc)
    /// property of an `@font-face` rule.
    /// Supports the `COLR` v0 table.
    @"color-colrv0",

    /// Supports the `COLR` v1 table.
    @"color-colrv1",

    /// Supports the `SVG` table.
    @"color-svg",

    /// Supports the `sbix` table.
    @"color-sbix",

    /// Supports the `CBDT` table.
    @"color-cbdt",

    /// Supports Variations
    /// The variations tech refers to the support of font variations
    variations,

    /// Supports Palettes
    /// The palettes tech refers to support for font palettes
    palettes,

    /// Supports Incremental
    /// The incremental tech refers to client support for incremental font loading, using either the range-request or the patch-subset method
    incremental,

    pub usingnamespace css.DefineEnumProperty(@This());
};

/// A `url()` value for the [src](https://drafts.csswg.org/css-fonts/#src-desc)
/// property in an `@font-face` rule.
pub const UrlSource = struct {
    /// The URL.
    url: Url,

    /// Optional `format()` function.
    format: ?FontFormat,

    /// Optional `tech()` function.
    tech: ArrayList(FontTechnology),

    pub fn parse(input: *css.Parser) Error!UrlSource {
        const url = try Url.parse(input);

        const format = if (input.tryParse(css.Parser.expectFunctionMatching, .{"format"}))
            try input.parseNestedBlock(FontFormat, {}, css.voidWrap(FontFormat, FontFormat.parse))
        else
            null;

        const tech = if (input.tryParse(css.Parser.expectFunctionMatching, .{"tech"})) tech: {
            const Fn = struct {
                pub fn parseNestedBlockFn(_: void, i: *css.Parser) Error!ArrayList(FontTechnology) {
                    return try i.parseList(FontTechnology, FontTechnology.parse);
                }
            };
            break :tech try input.parseNestedBlock(ArrayList(FontTechnology), {}, Fn.parseNestedBlockFn);
        } else null;

        return UrlSource{
            .url = url,
            .format = format,
            .tech = tech,
        };
    }

    pub fn toCss(this: *const UrlSource, comptime W: type, dest: *Printer(W)) PrintErr!void {
        try this.url.toCss(W, dest);
        if (this.format) |*format| {
            try dest.whitespace();
            try dest.writeStr("format(");
            try format.toCss(W, dest);
            try dest.writeChar(')');
        }

        if (this.tech.items.len != 0) {
            try dest.whitespace();
            try dest.writeStr("tech(");
            try css.to_css.fromList(FontTechnology, &this.tech.items, W, dest);
            try dest.writeChar(')');
        }
    }
};

/// A [@font-face](https://drafts.csswg.org/css-fonts/#font-face-rule) rule.
pub const FontFaceRule = struct {
    /// Declarations in the `@font-face` rule.
    proeprties: ArrayList(FontFaceProperty),
    /// The location of the rule in the source file.
    loc: Location,

    const This = @This();

    pub fn toCss(this: *const This, comptime W: type, dest: *Printer(W)) PrintErr!void {
        // #[cfg(feature = "sourcemap")]
        // dest.add_mapping(self.loc);

        try dest.writeStr("@font-face");
        try dest.whitespace();
        try dest.writeChar('{');
        dest.indent();
        const len = this.proeprties.items.len;
        for (this.proeprties.items, 0..) |*prop, i| {
            try dest.newline();
            prop.toCss(dest);
            if (i != len - 1 or !dest.minify) {
                try dest.writeChar(';');
            }
        }
        dest.dedent();
        try dest.newline();
        dest.writeChar('}');
    }
};

pub const FontFaceDeclarationParser = struct {
    const This = @This();

    pub const DeclarationParser = struct {
        pub const Declaration = FontFaceProperty;

        fn parseValue(this: *This, name: []const u8, input: *css.Parser) Error!Declaration {
            _ = this; // autofix
            const state = input.state();
            // todo_stuff.match_ignore_ascii_case
            if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "src")) {
                if (input.parseCommaSeparated(Source, Source.parse)) |sources| {
                    return .{ .sources = sources };
                }
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "font-family")) {
                if (FontFamily.parse(input)) |c| {
                    if (input.expectExhausted()) |_| {
                        return .{ .font_family = c };
                    }
                }
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "font-weight")) {
                if (Size2D(FontWeight).parse(input)) |c| {
                    if (input.expectExhausted()) |_| {
                        return .{ .font_weight = c };
                    }
                }
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "font-style")) {
                if (FontStyle.parse(input)) |c| {
                    if (input.expectExhausted()) |_| {
                        return .{ .font_style = c };
                    }
                }
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "font-stretch")) {
                if (Size2D(FontStretch).parse(input)) |c| {
                    if (input.expectExhausted()) |_| {
                        return .{ .font_stretch = c };
                    }
                }
            } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(name, "unicode-renage")) {
                if (input.parseList(UnicodeRange, UnicodeRange.parse)) |c| {
                    if (input.expectExhausted()) |_| {
                        return .{ .unicode_range = c };
                    }
                }
            } else {
                //
            }

            input.reset(&state);
            const opts = css.ParserOptions{};
            return .{
                .custom = try CustomProperty.parse(
                    CustomPropertyName.fromStr(name),
                    input,
                    &opts,
                ),
            };
        }
    };
};