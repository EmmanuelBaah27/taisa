/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,jsx,ts,tsx}',
    './src/**/*.{js,jsx,ts,tsx}',
  ],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      // ─── Primitive palettes ────────────────────────────────────────────
      // Use palette classes directly only when no semantic utility exists.
      // Per foundations.md decision rule: semantic utility > named palette > never raw hex.
      colors: {
        neutral: {
          white: '#ffffff',
          50:  '#f9f9f9',
          100: '#f3f3f3',
          200: '#e6e6e6',
          300: '#dadada',
          400: '#898989',
          500: '#5f646a',
          600: '#44484d',
          700: '#2b2e32',
          800: '#17181b',
          900: '#060707',
        },
        lime: {
          50:  '#f6fee8',
          100: '#edfbca',
          200: '#e0f7a4',
          300: '#d8f37c',
          400: '#d3f04e',
          500: '#cdec1a',  // primary CTA
          600: '#a0b90f',
          700: '#778700',  // readable lime text on white
          800: '#4e5a00',
          900: '#2b3201',
        },
        teal: {
          50:  '#e9f9fa',
          100: '#cdf2f5',
          200: '#a4e5eb',
          300: '#6cd0d9',
          400: '#3db1bb',
          500: '#006c76',
          600: '#00565d',
          700: '#004148',
          800: '#002e33',
          900: '#001b1f',
        },
        blush: {
          50:  '#faf1f7',
          100: '#f6e3ed',
          200: '#efcadd',
          300: '#e7accd',
          400: '#e093bf',
          500: '#d973b0',
          600: '#ba4f91',
          700: '#8a386c',
          800: '#60254a',
          900: '#361228',
        },
        orange: {
          50:  '#fcf2e8',
          100: '#f9e3cc',
          200: '#f6c89a',
          300: '#f4a759',
          400: '#f58100',
          500: '#e46300',
          600: '#b54d00',
          700: '#933f00',
          800: '#703100',
          900: '#4c2200',
        },
        blue: {
          50:  '#ebf5ff',
          100: '#cde6fe',
          200: '#91c9fd',
          300: '#68b5fc',
          400: '#329afb',
          500: '#0c79e6',
          600: '#0068c6',
          700: '#04539e',
          800: '#033a6e',
          900: '#01203c',
        },
        red: {
          50:  '#fff0ea',
          100: '#ffddd2',
          200: '#ffbfae',
          300: '#ff9480',
          400: '#ff5c4c',
          500: '#c60000',
          600: '#9f0000',
          700: '#7b0000',
          800: '#5d0000',
          900: '#3d0000',
        },
        green: {
          50:  '#e7f9e9',
          100: '#d6f5da',
          200: '#adebb5',
          300: '#86e091',
          400: '#4fd062',
          500: '#04851a',
          600: '#006417',
          700: '#165022',
          800: '#18391f',
          900: '#16281a',
        },
        yellow: {
          50:  '#fffbeb',
          100: '#fef3c7',
          200: '#fde68a',
          300: '#fbd34e',
          400: '#fcbf26',
          500: '#eb9707',
          600: '#c76d04',
          700: '#9b4807',
          800: '#5d2908',
          900: '#3b1603',
        },

        // ─── Semantic utilities ────────────────────────────────────────────
        // These are the only tokens components should reference.

        // Surfaces
        background:          '#ffffff',   // page background
        foreground:          '#060707',   // primary text
        subtle:              '#f9f9f9',   // hover fill, subtle sections
        muted:               '#f3f3f3',   // input bg, disabled bg
        'muted-foreground':  '#5f646a',   // secondary text, labels
        card:                '#ffffff',   // cards, panels
        'card-foreground':   '#060707',
        popover:             '#ffffff',
        'popover-foreground':'#060707',
        overlay:             'rgba(6,7,7,0.5)',

        // Primary action (lime)
        primary:             '#cdec1a',   // CTA button bg
        'primary-hover':     '#d3f04e',   // CTA hover
        'primary-foreground':'#060707',   // text on CTA button

        // Secondary
        secondary:            '#f3f3f3',
        'secondary-foreground':'#060707',

        // Accent (neutral-subtle — hover/active fill, NOT the lime CTA)
        accent:              '#f9f9f9',   // neutral-50
        'accent-foreground': '#060707',

        // Destructive
        destructive:          '#c60000',
        'destructive-hover':  '#9f0000',
        'destructive-foreground': '#ffffff',

        // Borders
        border:              '#e6e6e6',   // default border
        'border-subtle':     'rgba(6,7,7,0.08)', // hairline
        'border-strong':     '#dadada',   // elevated border
        'border-light':      '#e6e6e6',   // alias — used by Badge outline
        input:               '#e6e6e6',
        ring:                '#5f646a',

        // Disabled
        disabled:            '#e6e6e6',
        'disabled-foreground':'#898989',

        // Inverted
        'inverted-foreground':'#ffffff',

        // Extended text token
        'text-tertiary':     '#898989',   // → class: text-text-tertiary

        // Danger
        danger:              '#c60000',
        'danger-subtle':     '#fff0ea',
        'danger-border':     '#ff9480',
        'danger-text':       '#7b0000',

        // Success
        success:             '#04851a',
        'success-subtle':    '#e7f9e9',
        'success-text':      '#006417',

        // Warning (maps to orange)
        warning:             '#e46300',
        'warning-subtle':    '#fcf2e8',
        'warning-text':      '#b54d00',

        // Info
        info:                '#0c79e6',
        'info-subtle':       '#ebf5ff',
        'info-text':         '#0068c6',

        // Orange (warm variant — used by Badge)
        'orange-subtle':     '#fcf2e8',
        'orange-text':       '#933f00',

        // Accent badge tokens (teal — used by Badge accent variant)
        'accent-bg-light':   '#e9f9fa',
        'accent-fg-light':   '#004148',
        'accent-subtle':     '#e9f9fa',
        'accent-border':     '#6cd0d9',
      },

      // ─── Typography ─────────────────────────────────────────────────────
      // Composite text utilities (text-H1, text-lg-regular, etc.) are defined
      // in global.css @layer utilities. Raw font-size utilities below are
      // Tailwind defaults — use composite utilities in new components.
      fontFamily: {
        sans:          ['StrichpunktSans'],
        'sans-medium': ['StrichpunktSans-Medium'],
        'sans-bold':   ['StrichpunktSans-Bold'],
      },

      // ─── Border radius ───────────────────────────────────────────────────
      borderRadius: {
        '1':   '4px',
        '2':   '8px',
        '3':   '12px',
        '4':   '16px',
        '5':   '20px',
        '6':   '24px',
        'full':'9999px',
        // Aliases kept for backward compat during migration
        'sm':  '8px',
        'md':  '12px',
        'lg':  '16px',
        'xl':  '24px',
        '2xl': '24px',
        '3xl': '24px',
      },

      // ─── Shadows ────────────────────────────────────────────────────────
      boxShadow: {
        '2xs': '0 1px 0 0 rgba(0, 0, 0, 0.05)',
        'xs':  '0 1px 2px 0 rgba(23, 23, 23, 0.04)',
        'sm':  '0 1px 4px 0 rgba(23, 23, 23, 0.04)',
        'md':  '0 4px 6px -1px rgba(23, 23, 23, 0.08)',
        'lg':  '0 10px 15px -3px rgba(23, 23, 23, 0.08)',
        'xl':  '0 20px 25px -5px rgba(23, 23, 23, 0.08)',
      },
    },
  },
  plugins: [],
};
