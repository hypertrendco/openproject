import { Injectable } from '@angular/core';
import {XeokitServer} from "core-app/modules/ifc_models/xeokit/xeokit-server";
import {HttpClient, HttpHeaders} from "@angular/common/http";

export interface XeokitElements {
  canvasElement:HTMLElement;
  explorerElement:HTMLElement;
  toolbarElement:HTMLElement;
  navCubeCanvasElement:HTMLElement;
  sectionPlanesOverviewCanvasElement:HTMLElement;
}

export interface BCFCreationOptions {
  spacesVisible:boolean;
  spaceBoundariesVisible:boolean;
  openingsVisible:boolean;
}

@Injectable()
export class IFCViewerService {
  private viewer:any;

  public constructor(private readonly httpClient:HttpClient) {}

  public newViewer(elements:XeokitElements, projects:any[]) {
    import('@xeokit/xeokit-viewer/dist/main').then((XeokitViewerModule:any) => {
      let server = new XeokitServer();
      let viewerUI = new XeokitViewerModule.BIMViewer(server, elements);

      viewerUI.on("queryPicked", (event:any) => {
        const entity = event.entity; // Entity
        const metaObject = event.metaObject; // MetaObject
        alert(`Query result:\n\nObject ID = ${entity.id}\nIFC type = "${metaObject.type}"`);
      });

      viewerUI.loadProject(projects[0]["id"]);

      this.viewer = viewerUI;
      setTimeout(() => {
        const headers = new HttpHeaders().set("Content-Type", "application/json");
        const vp = this.saveBCFViewpoint({
          spacesVisible: true,
          spaceBoundariesVisible: true,
          openingsVisible: true
        });
        delete vp.bitmaps;

        console.log("vp", vp);
        this.httpClient
          .post(
            `/api/bcf/2.1/projects/demo-bcf-management-project/topics/00efc0da-b4d5-4933-bcb6-e01513ee2bcc/viewpoints`,
            vp,
            {
              headers: headers,
              withCredentials: true,
              responseType: 'json'
            }
          ).subscribe((data) => {
            console.log("Response of posting viewpoint", data);
          });
      }, 20000);
    });
  }

  public destroy() {
    if (!this.viewer) {
      return;
    }

    this.viewer._bcfViewpointsPlugin.destroy();
    this.viewer._canvasContextMenu.destroy();
    this.viewer._objectContextMenu.destroy();

    while (this.viewer.viewer._plugins.length > 0) {
      const plugin = this.viewer.viewer._plugins[0];
      plugin.destroy();
    }

    this.viewer.viewer.scene.destroy();
  }

  public saveBCFViewpoint(options:BCFCreationOptions):any {
    return this.viewer.saveBCFViewpoint(options);
  }
}