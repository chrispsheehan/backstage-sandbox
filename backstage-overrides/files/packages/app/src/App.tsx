import { createApp } from '@backstage/frontend-defaults';
import { createFrontendModule } from '@backstage/frontend-plugin-api';
import { githubAuthApiRef } from '@backstage/core-plugin-api';
import { SignInPage } from '@backstage/core-components';
import appPlugin from '@backstage/plugin-app';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import kubernetesPlugin from '@backstage/plugin-kubernetes/alpha';
import { navModule } from './modules/nav';
import { homeModule } from './modules/home';

const appModuleGitHubSignIn = createFrontendModule({
  pluginId: 'app',
  extensions: [
    appPlugin.getExtension('sign-in-page:app').override({
      params: {
        loader: async () => props => (
          <SignInPage
            {...props}
            provider={{
              id: 'github-auth-provider',
              title: 'GitHub',
              message: 'Sign in using your GitHub account',
              apiRef: githubAuthApiRef,
            }}
          />
        ),
      },
    }),
  ],
});

export default createApp({
  features: [
    appModuleGitHubSignIn,
    catalogPlugin,
    kubernetesPlugin,
    navModule,
    homeModule,
  ],
});
