import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import path from 'node:path';

const siteDirectory = process.cwd();

const config: Config = {
  title: 'Plinx',
  tagline: 'A parent-managed Plex experience for family media',
  favicon: 'favicon-512.png',
  url: 'https://bballdavis.github.io',
  baseUrl: '/Plinx/',
  organizationName: 'bballdavis',
  projectName: 'Plinx',
  trailingSlash: false,
  onBrokenLinks: 'throw',
  staticDirectories: ['static', '../assets/branding', '../screenshots'],
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  presets: [
    [
      'classic',
      {
        docs: {
          path: '.generated/docs',
          routeBasePath: 'docs',
          sidebarPath: './sidebars.ts',
          editUrl: ({docPath}) => `https://github.com/bballdavis/Plinx/edit/main/docs/${docPath}`,
          showLastUpdateAuthor: true,
          showLastUpdateTime: true,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [path.resolve(siteDirectory, 'src/plugins/dependencyStatus.mjs')],

  themeConfig: {
    image: 'plinx-social-card-1200x630.png',
    navbar: {
      logo: {
        alt: 'Plinx',
        src: 'plinx-lockup-on-light.svg',
        srcDark: 'plinx-lockup-on-dark.svg',
      },
      items: [
        {to: '/docs/user/getting-started', label: 'User Guide', position: 'left'},
        {to: '/docs/user/youtarr', label: 'Youtarr', position: 'left'},
        {to: '/docs/development/setup', label: 'Developers', position: 'left'},
        {to: '/docs/architecture/overview', label: 'Architecture', position: 'left'},
        {to: '/docs/maintenance/current-dependencies', label: 'Dependencies', position: 'left'},
        {
          href: 'https://github.com/bballdavis/Plinx',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Plinx',
          items: [
            {label: 'User guide', to: '/docs/user/getting-started'},
            {label: 'Parent guide', to: '/docs/user/parent-guide'},
            {label: 'Youtarr guide', to: '/docs/user/youtarr'},
            {label: 'Coming soon', to: '/docs/user/platform-status'},
          ],
        },
        {
          title: 'Contributors',
          items: [
            {label: 'Developer setup', to: '/docs/development/setup'},
            {label: 'Strimr integration', to: '/docs/architecture/strimr-integration'},
            {label: 'Current dependencies', to: '/docs/maintenance/current-dependencies'},
          ],
        },
        {
          title: 'Project',
          items: [
            {label: 'Privacy policy', href: 'https://github.com/bballdavis/Plinx/blob/main/PRIVACY_POLICY.md'},
            {label: 'License', href: 'https://github.com/bballdavis/Plinx/blob/main/LICENSE'},
            {label: 'Support', href: 'https://github.com/bballdavis/Plinx/issues'},
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Plinx contributors.`,
    },
    prism: {
      additionalLanguages: ['bash', 'swift', 'yaml'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
