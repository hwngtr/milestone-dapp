// Build the monochrome PPTX from the single-file HTML deck.
const fs = require('fs');
const pptxgen = require('pptxgenjs');

const html = fs.readFileSync('slides/code-demo-print.html', 'utf8');
const decode = (s) => s
  .replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"')
  .replace(/&#39;/g, "'")
  .replace(/&amp;/g, '&');
const strip = (s) => decode(String(s || '').replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();

const slidesData = [];
const sectionRe = /<section class="slide[^"]*" data-title="([^"]+)"[^>]*>([\s\S]*?)<\/section>/g;
let match;
while ((match = sectionRe.exec(html))) {
  const body = match[2];
  const heading = strip((body.match(/<h[12][^>]*>([\s\S]*?)<\/h[12]>/) || [])[1]) || match[1];
  const lede = strip((body.match(/<p class="lede">([\s\S]*?)<\/p>/) || [])[1]);
  const codes = Array.from(body.matchAll(/<pre>([\s\S]*?)<\/pre>/g))
    .map((m) => decode(m[1]));
  const bullets = Array.from(body.matchAll(/<li>([\s\S]*?)<\/li>/g)).map((m) => strip(m[1]));
  const notes = Array.from(body.matchAll(/<p class="small"[^>]*>([\s\S]*?)<\/p>/g)).map((m) => strip(m[1]));
  slidesData.push({ title: match[1], heading, lede, codes, bullets, notes, body });
}

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE';
pres.author = 'Hung Tran';
pres.title = 'Milestone: Solidity Code Demonstration';
pres.subject = 'Week 3-4 contract implementation';
const W = 13.3;

function base(title, number) {
  const slide = pres.addSlide();
  slide.background = { color: 'FFFFFF' };
  slide.addText('MILESTONE / WEEK 3-4', {
    x: 0.5, y: 0.28, w: 6, h: 0.24, fontSize: 10, bold: true,
    fontFace: 'Consolas', color: '555555', charSpacing: 2, margin: 0
  });
  slide.addText(title, {
    x: 0.5, y: 0.62, w: W - 1, h: 0.62, fontSize: 32, bold: true,
    fontFace: 'Georgia', color: '111111', margin: 0
  });
  slide.addText(String(number).padStart(2, '0'), {
    x: W - 1.0, y: 7.05, w: 0.5, h: 0.24, fontSize: 10,
    fontFace: 'Consolas', color: '555555', align: 'right', margin: 0
  });
  return slide;
}

function addCode(slide, code, y) {
  const lines = code.split('\n').length;
  const h = Math.max(0.5, lines * 0.178 + 0.22);
  slide.addShape(pres.shapes.RECTANGLE, {
    x: 0.5, y, w: W - 1, h, fill: { color: 'FFFFFF' }, line: { color: '111111', width: 1.2 }
  });
  slide.addText(code, {
    x: 0.62, y: y + 0.1, w: W - 1.24, h: h - 0.2, fontSize: 11, valign: 'top',
    fontFace: 'Consolas', color: '111111', margin: 0,
    breakLine: false, paraSpaceAfter: 0, lineSpacingMultiple: 1.0
  });
  return y + h + 0.16;
}

function addBullets(slide, items, y, fontSize) {
  if (!items.length) return;
  const runs = items.map((text) => ({
    text,
    options: { bullet: true, breakLine: true }
  }));
  slide.addText(runs, {
    x: 0.5, y, w: W - 1, h: 1.5, fontSize: fontSize || 13, valign: 'top',
    fontFace: 'Calibri', color: '111111', margin: 0,
    paraSpaceAfter: 4
  });
}

slidesData.forEach((data, i) => {
  const num = i + 1;
  const isDiagram = data.body.includes('class="diagram-full"');
  const slide = base(data.heading, num);

  if (num === 1) {
    slide.addText(data.lede, {
      x: 0.5, y: 1.45, w: W - 1, h: 0.9, fontSize: 20,
      fontFace: 'Georgia', color: '111111', margin: 0
    });
    slide.addShape(pres.shapes.RECTANGLE, {
      x: 0.5, y: 2.5, w: W - 1, h: 3.6,
      fill: { color: 'FFFFFF' }, line: { color: '111111', width: 1.5 }
    });
    const files = [
      'contracts/interfaces/ICampaign.sol - seven public functions and events',
      'contracts/Campaign.sol - escrow and state machine',
      'contracts/CampaignFactory.sol - clone deployment, no power over campaign funds'
    ];
    slide.addText(files.map((t) => ({ text: t, options: { bullet: true, breakLine: true } })), {
      x: 0.8, y: 2.8, w: W - 1.6, h: 3.0, fontSize: 17, valign: 'top',
      fontFace: 'Calibri', color: '111111', margin: 0, paraSpaceAfter: 14
    });
    slide.addText(data.notes[0] || '', {
      x: 0.5, y: 6.3, w: W - 1, h: 0.4, fontSize: 12,
      fontFace: 'Calibri', color: '555555', margin: 0
    });
    return;
  }

  if (isDiagram) {
    const name = data.title.startsWith('State') ? 'state-machine' : 'factory-clone';
    slide.addImage({
      path: `slides/diagrams/${name}.png`,
      x: 0.5, y: 1.4, w: W - 1, h: 4.9,
      sizing: { type: 'contain', w: W - 1, h: 4.9 },
      altText: data.heading
    });
    slide.addText(data.notes[0] || '', {
      x: 0.5, y: 6.45, w: W - 1, h: 0.5, fontSize: 12,
      fontFace: 'Calibri', color: '555555', margin: 0
    });
    return;
  }

  if (num === 9) {
    const half = Math.ceil(data.bullets.length / 2);
    slide.addText(data.bullets.slice(0, half).map((t) => ({ text: t, options: { bullet: true, breakLine: true } })), {
      x: 0.5, y: 1.5, w: 5.9, h: 4.9, fontSize: 15, valign: 'top', fontFace: 'Calibri', color: '111111', margin: 0, paraSpaceAfter: 8
    });
    slide.addText(data.bullets.slice(half).map((t) => ({ text: t, options: { bullet: true, breakLine: true } })), {
      x: 6.7, y: 1.5, w: 6.1, h: 4.9, fontSize: 15, valign: 'top', fontFace: 'Calibri', color: '111111', margin: 0, paraSpaceAfter: 8
    });
    return;
  }

  let y = 1.35;
  data.codes.forEach((code) => { y = addCode(slide, code, y); });
  addBullets(slide, data.bullets.slice(0, 3), Math.min(y + 0.05, 5.75), 13);
});

pres.writeFile({ fileName: 'milestone-week3-4-code-demo.pptx' })
  .then(() => console.log('wrote milestone-week3-4-code-demo.pptx, slides:', slidesData.length));
