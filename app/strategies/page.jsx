import { Suspense } from 'react';
import Strategies from '@/components/Strategies';

export const metadata = { title: 'Strategies · T2R Lab' };

export default function Page() {
  return <Suspense fallback={null}><Strategies /></Suspense>;
}
