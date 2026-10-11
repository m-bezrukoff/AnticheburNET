import { AnticheburNET } from '../../types';
import { ANTICHEBURNET_UCI_PACKAGE } from '../../../constants';

export async function getConfigSections(): Promise<AnticheburNET.ConfigSection[]> {
  return uci
    .load(ANTICHEBURNET_UCI_PACKAGE)
    .then(() => uci.sections(ANTICHEBURNET_UCI_PACKAGE));
}
