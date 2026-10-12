import Script from 'next/script';
import SHELL from './shell';

export default function Home() {
  return (
    <>
      <div dangerouslySetInnerHTML={{ __html: SHELL }} />
      <Script src="/lab.js" strategy="afterInteractive" />
    </>
  );
}
