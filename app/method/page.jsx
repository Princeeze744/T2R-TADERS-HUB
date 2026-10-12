import { Suspense } from 'react';
import Method from '@/components/Method';

export const metadata = { title: 'How it works · T2R Lab' };

export default function Page() {
  return <Suspense fallback={null}><Method /></Suspense>;
}
