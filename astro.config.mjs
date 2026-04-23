// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'Robotics Wiki',
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/2vyy/robotics-docs',
				},
			],
			sidebar: [
				{
					label: 'Onboarding',
					autogenerate: { directory: 'onboarding' },
				},
				{
					label: 'Milestones',
					autogenerate: { directory: 'milestones' },
				},
			],
		}),
	],
});
