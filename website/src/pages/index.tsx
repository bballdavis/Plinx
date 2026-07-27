import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import styles from './index.module.css';

const highlights = [
  ['Parent-managed', 'Choose libraries, profiles, ratings, and settings with a parent gate.'],
  ['Designed for families', 'A calm, playful Plex experience that keeps the focus on your media.'],
  ['Private by default', 'No analytics, crash reporting, or usage tracking from Plinx.'],
];

export default function Home() {
  const {siteConfig} = useDocusaurusContext();

  return (
    <Layout title="Family media, thoughtfully managed" description={siteConfig.tagline}>
      <main>
        <section className={styles.hero}>
          <div className={styles.heroContent}>
            <img className={styles.logo} src={useBaseUrl('logo_full_color.png')} alt="Plinx" />
            <p className={styles.eyebrow}>Coming soon for iPhone and iPad</p>
            <h1>Family media, thoughtfully managed.</h1>
            <p className={styles.lede}>
              Plinx is a parent-managed Plex client for browsing, watching, and downloading the media your family chooses.
            </p>
            <div className={styles.actions}>
              <Link className="button button--primary button--lg" to="/docs/user/getting-started">Explore the guide</Link>
              <Link className="button button--secondary button--lg" to="/docs/development/setup">Build from source</Link>
            </div>
          </div>
          <img className={styles.phone} src={useBaseUrl('iphone_home.png')} alt="Plinx home screen on iPhone" />
        </section>

        <section className={styles.section}>
          <div className={styles.cards}>
            {highlights.map(([title, body]) => (
              <article className={styles.card} key={title}>
                <h2>{title}</h2>
                <p>{body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className={`${styles.section} ${styles.split}`}>
          <div>
            <p className={styles.eyebrow}>For parents</p>
            <h2>Clear controls without the clutter.</h2>
            <p>Learn how profile selection, content ratings, library visibility, playback controls, and offline access work together.</p>
            <Link to="/docs/user/parent-guide">Read the parent guide →</Link>
          </div>
          <div>
            <p className={styles.eyebrow}>For contributors</p>
            <h2>Plinx and Strimr, clearly mapped.</h2>
            <p>Follow the supported sibling-checkout workflow, exact dependency pin, test layers, and ownership boundaries.</p>
            <Link to="/docs/architecture/strimr-integration">Understand the integration →</Link>
          </div>
        </section>
      </main>
    </Layout>
  );
}
