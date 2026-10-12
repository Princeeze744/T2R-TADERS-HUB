import { Suspense } from 'react';
import Desk from '@/components/Desk';

export const metadata = { title: 'Signal Desk · T2R Lab' };

export default function Page() {
  return <Suspense fallback={null}><Desk /></Suspense>;
}
