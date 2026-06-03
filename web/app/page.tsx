import Intro from "@/components/Intro";
import SiteHeader from "@/components/SiteHeader";
import Hero from "@/components/Hero";
import Problem from "@/components/Problem";
import HowItWorks from "@/components/HowItWorks";
import WowMoment from "@/components/WowMoment";
import SiteFooter from "@/components/SiteFooter";
import ScrollReveal from "@/components/ScrollReveal";

export default function Home() {
  return (
    <>
      <Intro />
      <SiteHeader />

      <main id="top">
        <Hero />

        <div className="wrap">
          <hr className="divider" />
        </div>

        <Problem />

        <div className="wrap">
          <hr className="divider" />
        </div>

        <HowItWorks />

        <div className="wrap">
          <hr className="divider" />
        </div>

        <WowMoment />
      </main>

      <SiteFooter />

      <ScrollReveal />
    </>
  );
}
