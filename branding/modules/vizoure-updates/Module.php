<?php declare(strict_types = 0);
/* Vizoure NMS — "Vizoure updates" module (Super admin only). Marker: VIZOURE_UPDATES_MODULE */

namespace Modules\VizoureUpdates;

use APP,
	CMenuItem,
	CWebUser,
	Zabbix\Core\CModule;

class Module extends CModule {

	public function init(): void {
		// Only Super admins get the menu entry; every action re-checks this server-side as well.
		if ((int) (CWebUser::$data['type'] ?? 0) !== USER_TYPE_SUPER_ADMIN) {
			return;
		}

		$administration = APP::Component()->get('menu.main')->find(_('Administration'));

		if ($administration !== null) {
			$administration->getSubMenu()->add(
				(new CMenuItem(_('Vizoure updates')))->setAction('vizoure.updates.view')
			);
		}
	}
}
