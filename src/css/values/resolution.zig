const std = @import("std");
const bun = @import("root").bun;
pub const css = @import("../css_parser.zig");
const Error = css.Error;
const ArrayList = std.ArrayListUnmanaged;
const Printer = css.Printer;
const PrintErr = css.PrintErr;
const CSSNumber = css.css_values.number.CSSNumber;
const CSSNumberFns = css.css_values.number.CSSNumberFns;
const Calc = css.css_values.calc.Calc;
const DimensionPercentage = css.css_values.percentage.DimensionPercentage;
const LengthPercentage = css.css_values.length.LengthPercentage;
const Length = css.css_values.length.Length;
const Percentage = css.css_values.percentage.Percentage;
const CssColor = css.css_values.color.CssColor;
const Image = css.css_values.image.Image;
const CSSInteger = css.css_values.number.CSSInteger;
const CSSIntegerFns = css.css_values.number.CSSIntegerFns;
const Angle = css.css_values.angle.Angle;
const Time = css.css_values.time.Time;
const CustomIdent = css.css_values.ident.CustomIdent;
const CustomIdentFns = css.css_values.ident.CustomIdentFns;
const Ident = css.css_values.ident.Ident;

/// A CSS `<resolution>` value.
pub const Resolution = union(enum) {
    /// A resolution in dots per inch.
    dpi: CSSNumber,
    /// A resolution in dots per centimeter.
    dpcm: CSSNumber,
    /// A resolution in dots per px.
    dppx: CSSNumber,

    pub fn parse(input: *css.Parser) Error!Resolution {
        // TODO: calc?
        const location = input.currentSourceLocation();
        const tok = try input.next();
        if (tok.* == .dimension) {
            const value = tok.dimension.num.value;
            const unit = tok.dimension.unit;
            // css.todo_stuff.match_ignore_ascii_case
            if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "dpi")) return .{ .dpi = value };
            if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "dpcm")) return .{ .dpcm = value };
            if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "dppx") or bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "x")) return .{ .dppx = value };
            return location.newUnexpectedTokenError(.{ .ident = unit });
        }
        return location.newUnexpectedTokenError(tok.*);
    }

    pub fn tryFromToken(token: *const css.Token) Error!Resolution {
        switch (token.*) {
            .dimension => |dim| {
                const value = dim.num.value;
                const unit = dim.unit;
                // todo_stuff.match_ignore_ascii_case
                if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "dpi")) {
                    return .{ .dpi = value };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "dpcm")) {
                    return .{ .dpcm = value };
                } else if (bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "dppx") or
                    bun.strings.eqlCaseInsensitiveASCIIICheckLength(unit, "x"))
                {
                    return .{ .dppx = value };
                } else {
                    @compileError(css.todo_stuff.errors);
                }
            },
            else => @compileError(css.todo_stuff.errors),
        }
    }

    // ~toCssImpl
    const This = @This();

    pub fn toCss(this: *const This, comptime W: type, dest: *Printer(W)) PrintErr!void {
        const value, const unit = switch (this.*) {
            .dpi => |dpi| .{ dpi, "dpi" },
            .dpcm => |dpcm| .{ dpcm, "dpcm" },
            .dppx => |dppx| if (dest.targets.isCompatible(.XResolutionUnit))
                .{ dppx, "x" }
            else
                .{ dppx, "dppx" },
        };

        return try css.serializer.serializeDimension(value, unit, W, dest);
    }
};