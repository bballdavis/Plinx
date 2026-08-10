import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  documentation: [
    'welcome',
    {
      type: 'category',
      label: 'User Guide',
      items: [
        'user/platform-status',
        'user/getting-started',
        'user/parent-guide',
        'user/using-plinx',
        'user/downloads-and-offline',
        'user/privacy-and-support',
      ],
    },
    {
      type: 'category',
      label: 'Youtarr',
      items: [
        'user/youtarr',
        'security/youtarr-privacy-and-safety',
        'architecture/youtarr-integration',
        'development/youtarr-live-smoke-tests',
      ],
    },
    {
      type: 'category',
      label: 'Developer Guide',
      items: [
        'README',
        'development/setup',
        'development/testing',
        'development/ui-testing',
        'development/ci',
        'development/testflight-delivery',
        'development/branch-pairing',
        'development/versioning-and-releases',
      ],
    },
    {
      type: 'category',
      label: 'Architecture',
      items: [
        'architecture/overview',
        'architecture/repo-boundaries',
        'architecture/runtime-build-graph',
        'architecture/source-tree',
        'architecture/strimr-integration',
      ],
    },
    {
      type: 'category',
      label: 'Safety, Product, and Release',
      items: [
        'product/branding',
        'security/privacy-and-safety',
        'release/app-store',
        'release/open-source-compliance',
      ],
    },
    {
      type: 'category',
      label: 'Maintenance',
      items: [
        'maintenance/current-dependencies',
        'maintenance/strimr-upstream-audit-2026-07-25',
        {
          type: 'category',
          label: 'Strimr contribution plans',
          items: [
            'maintenance/strimr-contributions/plex-clip-media-support',
            'maintenance/strimr-contributions/library-filtering-seams',
            'maintenance/strimr-contributions/flexible-plex-boolean-decoding',
            'maintenance/strimr-contributions/ios-clear-title-logos',
            'maintenance/strimr-contributions/recently-added-hub-classification',
            'maintenance/strimr-contributions/search-visibility-parity',
            'maintenance/strimr-contributions/download-integrity-and-index-recovery',
            'maintenance/strimr-contributions/offline-playback-progress',
            'maintenance/strimr-contributions/explicit-default-server-preference',
            'maintenance/strimr-contributions/shareplay-presentation-capability',
          ],
        },
        'maintenance/cleanup-roadmap',
      ],
    },
  ],
};

export default sidebars;
