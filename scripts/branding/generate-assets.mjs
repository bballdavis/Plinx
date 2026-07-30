#!/usr/bin/env node

import {createRequire} from 'node:module';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, '../..');
const require = createRequire(path.join(repositoryRoot, 'website/package.json'));
const sharp = require('sharp');
const potrace = require('potrace');

const checkOnly = process.argv.includes('--check');
const manifest = JSON.parse(
  await fs.readFile(path.join(repositoryRoot, 'assets/branding/brand-manifest.json'), 'utf8'),
);
const colors = manifest.palette;
const changed = [];

if (manifest.name !== 'Plinx') {
  throw new Error('Brand manifest product name must be exactly "Plinx"');
}

function repositoryPath(relativePath) {
  return path.join(repositoryRoot, relativePath);
}

async function emit(relativePath, content) {
  const destination = repositoryPath(relativePath);
  const data = Buffer.isBuffer(content) ? content : Buffer.from(content);

  if (checkOnly) {
    let existing;
    try {
      existing = await fs.readFile(destination);
    } catch {
      throw new Error(`Missing generated branding asset: ${relativePath}`);
    }
    if (existing.equals(data)) {
      return;
    }
    if (relativePath.endsWith('.png')) {
      const [existingImage, generatedImage] = await Promise.all([
        sharp(existing).raw().toBuffer({resolveWithObject: true}),
        sharp(data).raw().toBuffer({resolveWithObject: true}),
      ]);
      const sameShape =
        existingImage.info.width === generatedImage.info.width &&
        existingImage.info.height === generatedImage.info.height &&
        existingImage.info.channels === generatedImage.info.channels;
      if (sameShape && existingImage.data.equals(generatedImage.data)) {
        return;
      }
    }
    if (!existing.equals(data)) {
      throw new Error(`Generated branding asset is stale: ${relativePath}`);
    }
  }

  await fs.mkdir(path.dirname(destination), {recursive: true});
  await fs.writeFile(destination, data);
  changed.push(relativePath);
}

function trace(buffer, options = {}) {
  return new Promise((resolve, reject) => {
    potrace.trace(
      buffer,
      {
        threshold: 128,
        turdSize: 18,
        optCurve: true,
        optTolerance: 0.16,
        color: '#000000',
        background: 'transparent',
        ...options,
      },
      (error, svg) => {
        if (error) {
          reject(error);
        } else {
          resolve(svg);
        }
      },
    );
  });
}

async function tracedShape(relativePath) {
  const source = await sharp(repositoryPath(path.join('assets/branding', relativePath)))
    .ensureAlpha()
    .trim({background: {r: 0, g: 0, b: 0, alpha: 0}})
    .png()
    .toBuffer();
  const metadata = await sharp(source).metadata();
  const mask = await sharp(source)
    .extractChannel('alpha')
    .negate()
    .png()
    .toBuffer();
  const svg = await trace(mask);
  const match = svg.match(/<path[^>]+d="([^"]+)"/);
  if (!match) {
    throw new Error(`Unable to extract traced path from ${relativePath}`);
  }
  return {
    width: metadata.width,
    height: metadata.height,
    path: match[1],
  };
}

function svgDocument(width, height, body, definitions = '') {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
    definitions ? `<defs>${definitions}</defs>` : '',
    body,
    '</svg>',
    '',
  ].join('\n');
}

const brandGradient = `
  <linearGradient id="brandGradient" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="${colors.lime}"/>
    <stop offset="100%" stop-color="${colors.teal}"/>
  </linearGradient>`;

const ambientDefinitions = `
  <radialGradient id="ambientLime" cx="0.12" cy="0.04" r="0.72">
    <stop offset="0%" stop-color="${colors.lime}" stop-opacity="${manifest.ambient.limeOpacity}"/>
    <stop offset="100%" stop-color="${colors.lime}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="ambientTeal" cx="0.92" cy="0.92" r="0.76">
    <stop offset="0%" stop-color="${colors.teal}" stop-opacity="${manifest.ambient.tealOpacity}"/>
    <stop offset="100%" stop-color="${colors.teal}" stop-opacity="0"/>
  </radialGradient>`;

function group(shape, x, y, width, height, fill) {
  const scale = Math.min(width / shape.width, height / shape.height);
  const renderedWidth = shape.width * scale;
  const renderedHeight = shape.height * scale;
  const translateX = x + (width - renderedWidth) / 2;
  const translateY = y + (height - renderedHeight) / 2;
  return `<g transform="translate(${translateX} ${translateY}) scale(${scale})"><path d="${shape.path}" fill="${fill}" fill-rule="evenodd" clip-rule="evenodd"/></g>`;
}

function imageSetContents(filename) {
  return JSON.stringify(
    {
      images: [{filename, idiom: 'universal'}],
      info: {author: 'xcode', version: 1},
      properties: {
        'preserves-vector-representation': true,
        'template-rendering-intent': 'original',
      },
    },
    null,
    2,
  ) + '\n';
}

async function rasterize(svg, width, height, options = {}) {
  let pipeline = sharp(Buffer.from(svg), {density: 216}).resize(width, height, {
    fit: 'fill',
    kernel: sharp.kernel.lanczos3,
  });
  if (options.flatten) {
    pipeline = pipeline.flatten({background: options.flatten});
  }
  return pipeline.png({compressionLevel: 9, adaptiveFiltering: true}).toBuffer();
}

function horizontalLockup(
  mark,
  wordmark,
  wordFill,
  width = 1200,
  height = 320,
  markFill = 'url(#brandGradient)',
) {
  const markBox = {x: 42, y: 30, width: 254, height: 260};
  const wordBox = {x: 330, y: 76, width: 828, height: 168};
  return svgDocument(
    width,
    height,
    [
      group(mark, markBox.x, markBox.y, markBox.width, markBox.height, markFill),
      group(wordmark, wordBox.x, wordBox.y, wordBox.width, wordBox.height, wordFill),
    ].join('\n'),
    brandGradient,
  );
}

function stackedLockup(mark, wordmark, fill = colors.white) {
  return svgDocument(
    720,
    820,
    [
      group(mark, 150, 50, 420, 460, fill),
      group(wordmark, 92, 566, 536, 168, fill),
    ].join('\n'),
  );
}

function squareIcon(mark, treatment) {
  const markFill = treatment === 'dark' ? 'url(#brandGradient)' : colors.white;
  let background;
  let definitions = brandGradient;
  if (treatment === 'any') {
    background = '<rect width="1024" height="1024" fill="url(#brandGradient)"/>';
  } else if (treatment === 'dark') {
    background = `<rect width="1024" height="1024" fill="${colors.shell}"/>`;
  } else {
    background = '<rect width="1024" height="1024" fill="#EEEEEE"/>';
  }
  const fill = treatment === 'tinted' ? '#222222' : markFill;
  return svgDocument(
    1024,
    1024,
    `${background}\n${group(mark, 216, 190, 592, 644, fill)}`,
    definitions,
  );
}

function tvBackground(width, height) {
  return svgDocument(
    width,
    height,
    [
      `<rect width="${width}" height="${height}" fill="${colors.shell}"/>`,
      `<rect width="${width}" height="${height}" fill="url(#ambientLime)"/>`,
      `<rect width="${width}" height="${height}" fill="url(#ambientTeal)"/>`,
    ].join('\n'),
    ambientDefinitions,
  );
}

function tvForeground(mark, wordmark, width, height) {
  const contentWidth = width * manifest.tvOSIcon.foregroundWidthScale;
  const gap = height * 0.06;
  const markAspectRatio = mark.width / mark.height;
  const wordmarkAspectRatio = wordmark.width / wordmark.height;
  const wordmarkHeightRatio = 0.68;
  const markHeight = (contentWidth - gap)
    / (markAspectRatio + wordmarkHeightRatio * wordmarkAspectRatio);
  const markWidth = markHeight * markAspectRatio;
  const wordmarkHeight = markHeight * wordmarkHeightRatio;
  const wordmarkWidth = wordmarkHeight * wordmarkAspectRatio;
  const originX = (width - contentWidth) / 2;

  return svgDocument(
    width,
    height,
    [
      group(mark, originX, (height - markHeight) / 2, markWidth, markHeight, 'url(#brandGradient)'),
      group(
        wordmark,
        originX + markWidth + gap,
        (height - wordmarkHeight) / 2,
        wordmarkWidth,
        wordmarkHeight,
        colors.white,
      ),
    ].join('\n'),
    brandGradient,
  );
}

function topShelf(mark, wordmark, width, height) {
  const lockupWidth = Math.min(width * 0.46, 980);
  const lockupHeight = lockupWidth * (320 / 1200);
  const lockup = horizontalLockup(mark, wordmark, colors.white, 1200, 320)
    .replace(/^<\?xml[^>]+>\n/, '');
  const encoded = Buffer.from(lockup).toString('base64');
  return svgDocument(
    width,
    height,
    [
      `<rect width="${width}" height="${height}" fill="${colors.shell}"/>`,
      `<rect width="${width}" height="${height}" fill="url(#ambientLime)"/>`,
      `<rect width="${width}" height="${height}" fill="url(#ambientTeal)"/>`,
      `<image href="data:image/svg+xml;base64,${encoded}" x="${(width - lockupWidth) / 2}" y="${(height - lockupHeight) / 2}" width="${lockupWidth}" height="${lockupHeight}"/>`,
    ].join('\n'),
    ambientDefinitions,
  );
}

const mark = await tracedShape(manifest.sourceMark);
const wordmark = await tracedShape(manifest.sourceWordmark);

const markColor = svgDocument(
  mark.width,
  mark.height,
  `<path d="${mark.path}" fill="url(#brandGradient)"/>`,
  brandGradient,
);
const markWhite = svgDocument(
  mark.width,
  mark.height,
  `<path d="${mark.path}" fill="${colors.white}"/>`,
);
const markCharcoal = svgDocument(
  mark.width,
  mark.height,
  `<path d="${mark.path}" fill="${colors.shell}"/>`,
);
const wordmarkWhite = svgDocument(
  wordmark.width,
  wordmark.height,
  `<path d="${wordmark.path}" fill="${colors.white}" fill-rule="evenodd" clip-rule="evenodd"/>`,
);
const lockupOnLight = horizontalLockup(mark, wordmark, colors.shell);
const lockupOnDark = horizontalLockup(mark, wordmark, colors.white);
const lockupWhite = horizontalLockup(mark, wordmark, colors.white, 1200, 320, colors.white);
const stackedWhite = stackedLockup(mark, wordmark);

const vectorExports = {
  'assets/branding/plinx-mark-color.svg': markColor,
  'assets/branding/plinx-mark-white.svg': markWhite,
  'assets/branding/plinx-mark-charcoal.svg': markCharcoal,
  'assets/branding/plinx-wordmark-white.svg': wordmarkWhite,
  'assets/branding/plinx-lockup-on-light.svg': lockupOnLight,
  'assets/branding/plinx-lockup-on-dark.svg': lockupOnDark,
  'assets/branding/plinx-lockup-white.svg': lockupWhite,
  'assets/branding/plinx-lockup-stacked-white.svg': stackedWhite,
};
for (const [relativePath, svg] of Object.entries(vectorExports)) {
  await emit(relativePath, svg);
}

const appImageSets = {
  BrandMarkColor: ['brand-mark-color.svg', markColor],
  BrandMarkWhite: ['brand-mark-white.svg', markWhite],
  BrandMarkCharcoal: ['brand-mark-charcoal.svg', markCharcoal],
  BrandWordmarkWhite: ['brand-wordmark-white.svg', wordmarkWhite],
  BrandLockupOnLight: ['brand-lockup-on-light.svg', lockupOnLight],
  BrandLockupOnDark: ['brand-lockup-on-dark.svg', lockupOnDark],
  BrandLockupWhite: ['brand-lockup-white.svg', lockupWhite],
  BrandLockupStackedOnGradient: ['brand-lockup-stacked-on-gradient.svg', stackedWhite],
};
for (const [assetName, [filename, svg]] of Object.entries(appImageSets)) {
  const base = `PlinxApp/Resources/Assets.xcassets/${assetName}.imageset`;
  await emit(`${base}/${filename}`, svg);
  await emit(`${base}/Contents.json`, imageSetContents(filename));
}

await emit(
  'Packages/PlinxUI/Sources/PlinxUI/Resources/Assets.xcassets/plinx_loading_logo.imageset/plinx_loading_logo.png',
  await rasterize(markColor, 512, 512),
);

const rasterExports = {
  'assets/branding/plinx-mark-color.png': await rasterize(markColor, 1024, 1024),
  'assets/branding/plinx-mark-white.png': await rasterize(markWhite, 1024, 1024),
  'assets/branding/plinx-mark-charcoal.png': await rasterize(markCharcoal, 1024, 1024),
  'assets/branding/plinx-lockup-on-light.png': await rasterize(lockupOnLight, 1600, 427),
  'assets/branding/plinx-lockup-on-dark.png': await rasterize(lockupOnDark, 1600, 427),
  'assets/branding/plinx-lockup-stacked-white.png': await rasterize(stackedWhite, 1024, 1166),
};
for (const [relativePath, buffer] of Object.entries(rasterExports)) {
  await emit(relativePath, buffer);
}

const appIconAny = squareIcon(mark, 'any');
const appIconDark = squareIcon(mark, 'dark');
const appIconTinted = squareIcon(mark, 'tinted');
await emit(
  'PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/appicon-any.png',
  await rasterize(appIconAny, 1024, 1024, {flatten: colors.shell}),
);
await emit(
  'PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/appicon-dark.png',
  await rasterize(appIconDark, 1024, 1024, {flatten: colors.shell}),
);
await emit(
  'PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/appicon-tinted.png',
  await rasterize(appIconTinted, 1024, 1024, {flatten: '#EEEEEE'}),
);
await emit(
  'PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json',
  JSON.stringify(
    {
      images: [
        {filename: 'appicon-any.png', idiom: 'universal', platform: 'ios', size: '1024x1024'},
        {
          appearances: [{appearance: 'luminosity', value: 'dark'}],
          filename: 'appicon-dark.png',
          idiom: 'universal',
          platform: 'ios',
          size: '1024x1024',
        },
        {
          appearances: [{appearance: 'luminosity', value: 'tinted'}],
          filename: 'appicon-tinted.png',
          idiom: 'universal',
          platform: 'ios',
          size: '1024x1024',
        },
      ],
      info: {author: 'xcode', version: 1},
    },
    null,
    2,
  ) + '\n',
);
await emit('assets/branding/appicon-ios-any-1024.png', await rasterize(appIconAny, 1024, 1024, {flatten: colors.shell}));
await emit('assets/branding/appicon-ios-dark-1024.png', await rasterize(appIconDark, 1024, 1024, {flatten: colors.shell}));
await emit('assets/branding/appicon-ios-tinted-1024.png', await rasterize(appIconTinted, 1024, 1024, {flatten: '#EEEEEE'}));
await emit('assets/branding/favicon-512.png', await rasterize(appIconAny, 512, 512, {flatten: colors.shell}));

const launchGradient = svgDocument(
  2580,
  5592,
  [
    `<rect width="2580" height="5592" fill="${colors.shell}"/>`,
    '<rect width="2580" height="5592" fill="url(#launchLime)"/>',
    '<rect width="2580" height="5592" fill="url(#launchTeal)"/>',
  ].join('\n'),
  `
    <radialGradient id="launchLime" cx="0.08" cy="0.02" r="0.72">
      <stop offset="0%" stop-color="${colors.lime}" stop-opacity="0.06"/>
      <stop offset="100%" stop-color="${colors.lime}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="launchTeal" cx="0.94" cy="0.96" r="0.76">
      <stop offset="0%" stop-color="${colors.teal}" stop-opacity="0.08"/>
      <stop offset="100%" stop-color="${colors.teal}" stop-opacity="0"/>
    </radialGradient>`,
);
await emit(
  'PlinxApp/Resources/Assets.xcassets/LaunchGradient.imageset/launch_gradient.png',
  await rasterize(launchGradient, 2580, 5592, {flatten: colors.shell}),
);

const regularTV = [
  ['back.png', 400, 240, tvBackground(400, 240)],
  ['back@2x.png', 800, 480, tvBackground(800, 480)],
  ['front.png', 400, 240, tvForeground(mark, wordmark, 400, 240)],
  ['front@2x.png', 800, 480, tvForeground(mark, wordmark, 800, 480)],
];
for (const [filename, width, height, svg] of regularTV) {
  const layer = filename.startsWith('back') ? 'Back' : 'Front';
  await emit(
    `PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/App Icon.imagestack/${layer}.imagestacklayer/Content.imageset/${filename}`,
    await rasterize(svg, width, height, layer === 'Back' ? {flatten: colors.shell} : {}),
  );
}

for (const [layer, svg] of [
  ['Back', tvBackground(1280, 768)],
  ['Front', tvForeground(mark, wordmark, 1280, 768)],
]) {
  await emit(
    `PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/App Icon - App Store.imagestack/${layer}.imagestacklayer/Content.imageset/${layer.toLowerCase()}.png`,
    await rasterize(svg, 1280, 768, layer === 'Back' ? {flatten: colors.shell} : {}),
  );
}

await emit(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/Top Shelf Image.imageset/top-shelf.png',
  await rasterize(topShelf(mark, wordmark, 1920, 720), 1920, 720, {flatten: colors.shell}),
);
await emit(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/Top Shelf Image Wide.imageset/top-shelf-wide.png',
  await rasterize(topShelf(mark, wordmark, 2320, 720), 2320, 720, {flatten: colors.shell}),
);

const socialCard = svgDocument(
  1200,
  630,
  [
    `<rect width="1200" height="630" fill="${colors.shell}"/>`,
    '<rect width="1200" height="630" fill="url(#ambientLime)"/>',
    '<rect width="1200" height="630" fill="url(#ambientTeal)"/>',
    group(mark, 170, 145, 330, 340, 'url(#brandGradient)'),
    group(wordmark, 535, 220, 500, 190, colors.white),
  ].join('\n'),
  `${brandGradient}${ambientDefinitions}`,
);
await emit('assets/branding/plinx-social-card-1200x630.png', await rasterize(socialCard, 1200, 630, {flatten: colors.shell}));

const websiteHero = svgDocument(
  2400,
  1200,
  [
    `<rect width="2400" height="1200" fill="${colors.shell}"/>`,
    '<rect width="2400" height="1200" fill="url(#ambientLime)"/>',
    '<rect width="2400" height="1200" fill="url(#ambientTeal)"/>',
  ].join('\n'),
  ambientDefinitions,
);
await emit(
  'assets/branding/plinx-ambient-hero-2400x1200.png',
  await rasterize(websiteHero, 2400, 1200, {flatten: colors.shell}),
);

async function validateRaster(relativePath, width, height, {alpha} = {}) {
  const metadata = await sharp(repositoryPath(relativePath)).metadata();
  if (metadata.width !== width || metadata.height !== height) {
    throw new Error(
      `${relativePath} is ${metadata.width}x${metadata.height}; expected ${width}x${height}`,
    );
  }
  if (metadata.space !== 'srgb') {
    throw new Error(`${relativePath} must be sRGB; found ${metadata.space}`);
  }
  if (alpha === false && metadata.hasAlpha) {
    throw new Error(`${relativePath} must be opaque`);
  }
  if (alpha === true && !metadata.hasAlpha) {
    throw new Error(`${relativePath} must preserve transparency`);
  }
}

await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/appicon-any.png',
  1024,
  1024,
  {alpha: false},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/appicon-dark.png',
  1024,
  1024,
  {alpha: false},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/appicon-tinted.png',
  1024,
  1024,
  {alpha: false},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back.png',
  400,
  240,
  {alpha: false},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front.png',
  400,
  240,
  {alpha: true},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/Top Shelf Image.imageset/top-shelf.png',
  1920,
  720,
  {alpha: false},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/Top Shelf Image Wide.imageset/top-shelf-wide.png',
  2320,
  720,
  {alpha: false},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/back.png',
  1280,
  768,
  {alpha: false},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/front.png',
  1280,
  768,
  {alpha: true},
);
await validateRaster(
  'PlinxApp/Resources/Assets.xcassets/LaunchGradient.imageset/launch_gradient.png',
  2580,
  5592,
  {alpha: false},
);
await validateRaster('assets/branding/favicon-512.png', 512, 512, {alpha: false});
await validateRaster(
  'assets/branding/plinx-social-card-1200x630.png',
  1200,
  630,
  {alpha: false},
);
await validateRaster(
  'assets/branding/plinx-ambient-hero-2400x1200.png',
  2400,
  1200,
  {alpha: false},
);
await validateRaster('assets/branding/plinx-mark-color.png', 1024, 1024, {alpha: true});
await validateRaster(
  'assets/branding/plinx-lockup-on-dark.png',
  1600,
  427,
  {alpha: true},
);

for (const relativePath of Object.keys(vectorExports)) {
  const svg = await fs.readFile(repositoryPath(relativePath), 'utf8');
  if (!svg.includes('<svg') || !svg.includes('<path') || svg.includes('<text')) {
    throw new Error(`${relativePath} must contain outlined SVG paths and no live text`);
  }
}

const tintedPixels = await sharp(
  repositoryPath('PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset/appicon-tinted.png'),
).raw().toBuffer({resolveWithObject: true});
for (let index = 0; index < tintedPixels.data.length; index += tintedPixels.info.channels) {
  const red = tintedPixels.data[index];
  const green = tintedPixels.data[index + 1];
  const blue = tintedPixels.data[index + 2];
  if (red !== green || green !== blue) {
    throw new Error('Tinted app icon must contain grayscale artwork only');
  }
}

const tvFront = await sharp(
  repositoryPath(
    'PlinxApp/Resources/Assets.xcassets/AppIconTV.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front.png',
  ),
).ensureAlpha().raw().toBuffer({resolveWithObject: true});
if (tvFront.data[3] !== 0) {
  throw new Error('tvOS foreground layer must have transparent corners');
}

function alphaBounds(rawResult) {
  const {data, info} = rawResult;
  let minX = info.width;
  let minY = info.height;
  let maxX = -1;
  let maxY = -1;

  for (let y = 0; y < info.height; y += 1) {
    for (let x = 0; x < info.width; x += 1) {
      const alpha = data[(y * info.width + x) * info.channels + 3];
      if (alpha > 8) {
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }
  }

  return {minX, minY, maxX, maxY};
}

const tvFrontBounds = alphaBounds(tvFront);
const tvFrontWidthRatio = (tvFrontBounds.maxX - tvFrontBounds.minX + 1) / tvFront.info.width;
if (tvFrontWidthRatio < 0.69) {
  throw new Error(`tvOS foreground lockup is too small (${tvFrontWidthRatio.toFixed(3)} width ratio)`);
}

const lockupPixels = await sharp(
  repositoryPath('assets/branding/plinx-lockup-on-dark.png'),
).ensureAlpha().raw().toBuffer({resolveWithObject: true});
const pCounterAlpha = lockupPixels.data[
  (181 * lockupPixels.info.width + 742) * lockupPixels.info.channels + 3
];
if (pCounterAlpha > 8) {
  throw new Error('Plinx wordmark P counter must remain transparent');
}

const whiteLockupPixels = await sharp(Buffer.from(lockupWhite))
  .ensureAlpha()
  .raw()
  .toBuffer({resolveWithObject: true});
for (
  let index = 0;
  index < whiteLockupPixels.data.length;
  index += whiteLockupPixels.info.channels
) {
  const alpha = whiteLockupPixels.data[index + 3];
  if (
    alpha > 8
    && (
      whiteLockupPixels.data[index] < 250
      || whiteLockupPixels.data[index + 1] < 250
      || whiteLockupPixels.data[index + 2] < 250
    )
  ) {
    throw new Error('White lockup must use white artwork for both the loop and wordmark');
  }
}

if (checkOnly) {
  console.log('Plinx branding assets are current.');
} else {
  console.log(`Generated ${changed.length} Plinx branding assets.`);
}
